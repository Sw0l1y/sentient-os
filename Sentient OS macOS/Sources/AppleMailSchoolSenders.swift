// AppleMailSchoolSenders.swift
// The one list of school notification senders whose mail is let through Apple Mail's
// list/bulk/promotions junk rules (SCHOOL-SPEC Part A). Assignment, due-date and course-update
// notices carry List-Unsubscribe / List-Id / Precedence: bulk headers and often land in a
// Promotions category, so without this they were forced to junk before the model saw them.
// Real spam signals still apply: Mail's junk level, X-Spam headers and Junk/Spam mailboxes.
// Matching is on the From address's domain only (exact or a subdomain), never the display name.
// Foundation only; a standalone test compiles it with AppleMailMIME.swift.

import Foundation

nonisolated enum SchoolSenders {
    /// Schoology, ALEKS / McGraw Hill, Savvas Realize and Google Classroom notification domains.
    /// Add a domain here (and only here) to let another school service's notices through.
    static let domains: [String] = [
        "schoology.com",
        "aleks.com",
        "mheducation.com",
        "mcgrawhill.com",
        "savvas.com",
        "savvasrealize.com",
        "classroom.google.com",
    ]

    /// True when the From header's single address belongs to a school domain or one of its subdomains.
    static func contains(from header: String?) -> Bool {
        guard let domain = senderDomain(header) else { return false }
        return domains.contains { domain == $0 || domain.hasSuffix("." + $0) }
    }

    /// The domain of the one address in a From header ("Schoology <noreply@schoology.com>" ->
    /// "schoology.com"), lowercased. Nil for no address, several addresses, or a malformed one, so an
    /// ambiguous header never earns an exemption. Also used as the coarse sender label in reports.
    static func senderDomain(_ header: String?) -> String? {
        guard let header else { return nil }
        let address: Substring
        if let open = header.lastIndex(of: "<") {
            guard header.filter({ $0 == "<" }).count == 1,
                  let close = header[open...].firstIndex(of: ">") else { return nil }
            address = header[header.index(after: open)..<close]
        } else {
            guard !header.contains(",") else { return nil }
            address = Substring(header)
        }
        let parts = address.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let domain = parts[1].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !domain.isEmpty, !domain.hasPrefix("."), !domain.hasSuffix("."), !domain.contains(".."),
              domain.contains("."),
              domain.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." }) else { return nil }
        return domain
    }
}
