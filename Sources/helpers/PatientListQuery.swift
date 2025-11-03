//
//  PatientListQuery.swift
//  SMART-on-FHIR
//
//  Created by Pascal Pfiffner on 2/9/15.
//  Copyright (c) 2015 SMART Health IT. All rights reserved.
//

import Foundation
import ModelsR5

public final class PatientListQuery {
	private let pageSize: Int
	private let additionalParameters: [URLQueryItem]
	private var nextLink: URL?

	public init(pageSize: Int = 50, additionalParameters: [URLQueryItem] = []) {
		self.pageSize = pageSize
		self.additionalParameters = additionalParameters
	}

	public func reset() {
		nextLink = nil
	}

	func makePath(order: PatientListOrder) -> String {
		if let nextLink {
			return nextLink.absoluteString
		}

		var items = additionalParameters
		items.append(URLQueryItem(name: "_sort", value: order.rawValue))
		items.append(URLQueryItem(name: "_count", value: "\(pageSize)"))

		guard !items.isEmpty else {
			return "Patient"
		}

		let query = items.compactMap { item -> String? in
			guard let value = item.value else { return nil }
			guard
				let encodedName = item.name.addingPercentEncoding(
					withAllowedCharacters: .urlQueryAllowed),
				let encodedValue = value.addingPercentEncoding(
					withAllowedCharacters: .urlQueryAllowed)
			else {
				return nil
			}
			return "\(encodedName)=\(encodedValue)"
		}.joined(separator: "&")

		guard !query.isEmpty else {
			return "Patient"
		}

		return "Patient?\(query)"
	}

	func update(with bundle: ModelsR5.Bundle) {
		if let next = bundle.link?.first(where: { $0.relation.value == .next })?.url.value?.url {
			nextLink = next
		} else {
			nextLink = nil
		}
	}

	var hasMore: Bool {
		nextLink != nil
	}
}
