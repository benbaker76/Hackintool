//
//  Localization.swift
//  Hackintool
//
//  Localizable.strings is keyed by the English UI text, so a missing
//  translation falls back to the key itself.
//

import Foundation

/// Returns the localized string for an English UI string.
func L(_ key: String) -> String {
	return Bundle.main.localizedString(forKey: key, value: key, table: nil)
}

/// Returns the localized string for an English format string, then formats it.
func L(_ key: String, _ arguments: CVarArg...) -> String {
	return String(format: L(key), arguments: arguments)
}

/// Returns the localized tooltip for a control identifier ("TT_<identifier>"), if one exists.
func toolTip(_ identifier: String) -> String? {
	let key = "TT_" + identifier
	let value = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
	return value == key ? nil : value
}
