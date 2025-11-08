//
//  PatientList.swift
//  SMART-on-FHIR
//
//  Created by Pascal Pfiffner on 2/4/15.
//  Copyright (c) 2015 SMART Health IT. All rights reserved.
//

import FHIRClient
import Foundation
import ModelsR5

private struct SendableWeakPatientList: @unchecked Sendable {
	weak var value: PatientList?
}

private struct SendableServerReference: @unchecked Sendable {
	let value: Server
}

public enum PatientListStatus: Int {
	case unknown
	case initialized
	case loading
	case ready
}

/// A class to hold a list of patients, created from a query performed against a FHIRServer.
///
/// The `retrieve` method must be called at least once so the list can start retrieving patients from the server. Use
/// the `onStatusUpdate` and `onPatientUpdate` blocks to keep informed about status changes.
///
/// You can use subscript syntax to safely retrieve a patient from the list: patientList[5]
open class PatientList {

	/// Current list status.
	open var status: PatientListStatus = .unknown {
		didSet {
			onStatusUpdate?(lastStatusError)
			lastStatusError = nil
		}
	}
	fileprivate var lastStatusError: Error? = nil

	/// A block executed whenever the receiver's status changes.
	open var onStatusUpdate: ((Error?) -> Void)?

	/// The patients currently in this list.
	var patients: [ModelsR5.Patient]? {
		didSet {
			// make sure the expected number of patients is at least as high as the number of patients we have
			expectedNumberOfPatients = max(expectedNumberOfPatients, actualNumberOfPatients)
			createSections()
			onPatientUpdate?()
		}
	}

	/// A block to be called when the `patients` property changes.
	open var onPatientUpdate: (() -> Void)?

	fileprivate(set) open var expectedNumberOfPatients: UInt = 0

	/// The number of patients currently in the list.
	open var actualNumberOfPatients: UInt {
		return UInt(patients?.count ?? 0)
	}

	var sections: [PatientListSection] = []

	open var numSections: Int {
		return sections.count
	}

	open internal(set) var sectionIndexTitles: [String] = []

	/// How to order the list.
	open var order = PatientListOrder.nameFamilyASC

	/// The query used to create the list.
	public let query: PatientListQuery

	/// Indicating whether not all patients have yet been loaded.
	open var hasMore: Bool {
		if patients == nil {
			return true
		}
		return query.hasMore
	}

	private var currentTask: _Concurrency.Task<Void, Never>?

	public init(query: PatientListQuery) {
		self.query = query
		self.status = .initialized
	}

	// MARK: - Patients & Sections

	subscript(index: Int) -> PatientListSection? {
		if sections.count > index {
			return sections[index]
		}
		return nil
	}

	/**
	Create sections from our patients. On iOS we could use UILocalizedCollection, but it's cumbersome on
	non-NSObject subclasses. Assumes that the patient list is already ordered
	*/
	func createSections() {
		if let patients = self.patients {
			sections = [PatientListSection]()
			sectionIndexTitles = [String]()

			var n = 0
			var lastTitle: Character = "$"
			var lastSection = PatientListSection(title: "")
			for patient in patients {
				let pre: Character = patient.displayNameFamilyGiven.first ?? "$"  // TODO: use another method depending on current ordering
				if pre != lastTitle {
					lastTitle = pre
					lastSection = PatientListSection(title: String(lastTitle))
					lastSection.offset = n
					sections.append(lastSection)
					sectionIndexTitles.append(lastSection.title)
				}
				lastSection.add(patient: patient)
				n += 1
			}

			// not all patients fetched yet?
			if actualNumberOfPatients < expectedNumberOfPatients {
				let sham = PatientListSectionPlaceholder(title: "↓")
				sham.holdingForNumPatients = expectedNumberOfPatients - actualNumberOfPatients
				sections.append(sham)
				sectionIndexTitles.append(sham.title)
			}
		} else {
			sections = []
			sectionIndexTitles = []
		}
	}

	// MARK: - Patient Loading

	/**
	Executes the patient query against the given FHIR server and updates the receiver's `patients` property when done.
	
	- parameter fromServer: A FHIRServer instance to query the patients from
	*/
	open func retrieve(fromServer server: Server) {
		patients = nil
		expectedNumberOfPatients = 0
		query.reset()
		retrieveBatch(fromServer: server)
	}

	/**
	Attempts to retrieve the next batch of patients. You should check `hasMore` before calling this method.
	
	- parameter fromServer: A FHIRServer instance to retrieve the batch from
	*/
	open func retrieveMore(fromServer server: Server) {
		retrieveBatch(fromServer: server, appendPatients: true)
	}

	func retrieveBatch(fromServer server: Server, appendPatients: Bool = false) {
		status = .loading
		let path = query.makePath(order: order)
		let operation = DecodingFHIRRequestOperation<ModelsR5.Bundle>(
			path: path,
			headers: ["Accept": "application/fhir+json"]
		)
		currentTask?.cancel()
		let listRef = SendableWeakPatientList(value: self)
		let serverRef = SendableServerReference(value: server)
		currentTask = _Concurrency.Task {
			guard let list = listRef.value else { return }
			await list.performRetrieveBatch(
				server: serverRef.value,
				operation: operation,
				appendPatients: appendPatients
			)
		}
	}

	@MainActor
	private func handle(bundle: ModelsR5.Bundle, appendPatients: Bool) {
		query.update(with: bundle)
		let newPatients =
			bundle.entry?
			.compactMap { entry -> ModelsR5.Patient? in
				guard let resource = entry.resource else { return nil }
				if case .patient(let patient) = resource {
					return patient
				}
				return nil
			} ?? []
		let total = bundle.total?.value?.integer
		if let total, total >= 0 {
			expectedNumberOfPatients = UInt(total)
		}
		let existing = appendPatients ? (patients ?? []) : []
		let combined = appendPatients ? existing + newPatients : newPatients
		patients = order.ordered(combined)
		status = .ready
	}

	@MainActor
	private func performRetrieveBatch(
		server: Server,
		operation: DecodingFHIRRequestOperation<ModelsR5.Bundle>,
		appendPatients: Bool
	) async {
		defer { currentTask = nil }
		do {
			let bundle = try await server.execute(operation)
			handle(bundle: bundle, appendPatients: appendPatients)
		} catch is CancellationError {
			status = .ready
		} catch {
			lastStatusError = error
			status = .ready
		}
	}
}

/// A patient list holding all available patients.
open class PatientListAll: PatientList {

	public init() {
		super.init(query: PatientListQuery())
	}
}

/// Patients are divided into sections, e.g. by first letter of their family name. This class holds patients belonging
/// to one section.
open class PatientListSection {

	open var title: String
	var patients: [ModelsR5.Patient]?
	var numPatients: UInt {
		return UInt(patients?.count ?? 0)
	}

	/// How many patients are in sections coming before this one. Only valid in context of a PatientList.
	open var offset: Int = 0

	public init(title: String) {
		self.title = title
	}

	func add(patient: ModelsR5.Patient) {
		if nil == patients {
			patients = [ModelsR5.Patient]()
		}
		patients!.append(patient)
	}

	subscript(index: Int) -> ModelsR5.Patient? {
		if let patients = patients, patients.count > index {
			return patients[index]
		}
		return nil
	}
}

class PatientListSectionPlaceholder: PatientListSection {

	override var numPatients: UInt {
		return holdingForNumPatients
	}
	var holdingForNumPatients: UInt = 0
}
