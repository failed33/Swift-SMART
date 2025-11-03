//
//  PatientListOrder.swift
//  SMART-on-FHIR
//
//  Created by Pascal Pfiffner on 2/9/15.
//  Copyright (c) 2015 SMART Health IT. All rights reserved.
//

import Foundation
import ModelsR5

/// An enum to define how a list of patients should be ordered.
public enum PatientListOrder: String {

	/// Order by given name, family name, birthday.
	case nameGivenASC = "given,family,birthdate"

	// Order by family name, given name, birthday.
	case nameFamilyASC = "family,given,birthdate"

	/// Order by birthdate, family name, given name.
	case birthDateASC = "birthdate,family,given"

	/**
	Applies the receiver's ordering to a given list of patients.
	
	- parameter patients: A list of Patient instances
	- returns: An ordered list of Patient instances
	*/
	func ordered(_ patients: [Patient]) -> [Patient] {
		switch self {
		case .nameGivenASC:
			return patients.sorted {
				let given = $0.compareNameGiven(toPatient: $1)
				if 0 != given {
					return given < 0
				}
				let family = $0.compareNameFamily(toPatient: $1)
				if 0 != family {
					return family < 0
				}
				let birth = $0.compareBirthDate(toPatient: $1)
				return birth < 0
			}
		case .nameFamilyASC:
			return patients.sorted {
				let family = $0.compareNameFamily(toPatient: $1)
				if 0 != family {
					return family < 0
				}
				let given = $0.compareNameGiven(toPatient: $1)
				if 0 != given {
					return given < 0
				}
				let birth = $0.compareBirthDate(toPatient: $1)
				return birth < 0
			}
		case .birthDateASC:
			return patients.sorted {
				let birth = $0.compareBirthDate(toPatient: $1)
				if 0 != birth {
					return birth < 0
				}
				let family = $0.compareNameFamily(toPatient: $1)
				if 0 != family {
					return family < 0
				}
				let given = $0.compareNameGiven(toPatient: $1)
				return given < 0
			}
		}
	}
}

extension Patient {

	func compareNameGiven(toPatient: Patient) -> Int {
		let a = name?.first?.given?.first?.value?.string ?? "ZZZ"
		let b = toPatient.name?.first?.given?.first?.value?.string ?? "ZZZ"
		return a.compare(b).rawValue
	}

	func compareNameFamily(toPatient: Patient) -> Int {
		let a = name?.first?.family?.string ?? "ZZZ"
		let b = toPatient.name?.first?.family?.string ?? "ZZZ"
		return a.compare(b).rawValue
	}

	func compareBirthDate(toPatient: Patient) -> Int {
		let nodate = Date(timeIntervalSince1970: -70 * 365.25 * 24 * 3600)
		let a = birthDate?.nsDate ?? nodate
		let b = toPatient.birthDate?.nsDate ?? nodate
		return a.compare(b).rawValue
	}

	var displayNameFamilyGiven: String {
		guard let humanName = name?.first else {
			return "Unnamed Patient".fhir_localized
		}

		let givenNames = humanName.given?
			.compactMap { primitive -> String? in
				guard let value = primitive.value?.string, !value.isEmpty else { return nil }
				return value
			}
			.joined(separator: " ")

		let familyName = humanName.family?.string

		if let given = givenNames, !given.isEmpty {
			if let family = familyName, !family.isEmpty {
				return "\(family), \(given)"
			}
			return given
		}

		if let family = familyName, !family.isEmpty {
			let prefix = (gender?.value == .male) ? "Mr.".fhir_localized : "Ms.".fhir_localized
			return "\(prefix) \(family)"
		}

		return "Unnamed Patient".fhir_localized
	}

	var currentAge: String {
		guard let dateOfBirth = birthDate?.nsDate else {
			return ""
		}

		let calendar = Calendar.current
		var components = calendar.dateComponents([.year, .month], from: dateOfBirth, to: Date())

		if let year = components.year, year < 1 {
			if let month = components.month, month < 1 {
				components = calendar.dateComponents([.day], from: dateOfBirth, to: Date())
				if let day = components.day, day < 1 {
					return "just born".fhir_localized
				}
				let label =
					(components.day == 1) ? "day old".fhir_localized : "days old".fhir_localized
				return "\(components.day ?? 0) \(label)"
			}
			let label =
				(components.month == 1) ? "month old".fhir_localized : "months old".fhir_localized
			return "\(components.month ?? 0) \(label)"
		}

		if let months = components.month, months != 0, let years = components.year {
			let yearLabel = (years == 1) ? "yr".fhir_localized : "yrs".fhir_localized
			let monthLabel = (months == 1) ? "mth".fhir_localized : "mths".fhir_localized
			return "\(years) \(yearLabel), \(months) \(monthLabel)"
		}

		if let years = components.year {
			let yearLabel = (years == 1) ? "year old".fhir_localized : "years old".fhir_localized
			return "\(years) \(yearLabel)"
		}

		return ""
	}
}
