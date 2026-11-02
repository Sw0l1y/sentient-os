#!/usr/bin/env python3
"""School notification senders are exempt from Apple Mail's list/bulk/Promotions junk rules only.
Compiles the production AppleMailSchoolSenders.swift and AppleMailMIME.swift whole, plus
AppleMailRow and AppleMailSource.forcedJunk sliced from AppleMailSource.swift. Checks the From-domain
match (exact or subdomain, never a look-alike, a display name or a second address), that list,
unsubscribe and bulk headers no longer force junk for these senders, that real spam signals still
do, and that the mail triage prompt says school notices are worth keeping. No Mail data is read.
"""
from pathlib import Path
import platform
import re
import subprocess
import tempfile

APP = Path(__file__).resolve().parents[1] / 'Sentient OS macOS'


def member(source, signature):
    start = source.index(signature)
    end = source.index('{', start) + 1
    depth = 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


mail_source = (APP / 'Sources/AppleMailSource.swift').read_text()
triage = (APP / 'Engine/Triage.swift').read_text()
assert 'School notifications about assignments, due dates, grades and course updates' in triage, \
    'the mail triage prompt tells the model school notices are worth keeping'

error_enum = re.search(r'^nonisolated enum AppleMailError: Error \{[^}]*\}', mail_source, re.M).group(0)
PRODUCTION = '\n'.join((
    'import Foundation',
    error_enum,
    member(mail_source, 'nonisolated struct AppleMailRow'),
    'nonisolated enum AppleMailSource {',
    member(mail_source, '    static func forcedJunk(row: AppleMailRow, headers: [String: String]) -> Bool'),
    '}',
))

TESTS = r'''
import Foundation
@main struct Tests {
    @MainActor static var count = 0
    @MainActor static func check(_ value: Bool, _ label: String) { precondition(value, label); count += 1 }

    static func row(excluded: Bool, bulkOnly: Bool) -> AppleMailRow {
        AppleMailRow(id: 1, account: "A", messageID: "<1@fixture>", date: Date(), excluded: excluded, sent: false,
                     previewJunk: excluded, bulkOnly: bulkOnly)
    }

    @MainActor static func main() {
        check(Set(SchoolSenders.domains) == ["schoology.com", "aleks.com", "mheducation.com", "mcgrawhill.com",
                                            "savvas.com", "savvasrealize.com", "classroom.google.com"],
              "one named list holds exactly the school notification domains")
        for from in ["Schoology <noreply@schoology.com>", "no-reply@mail.schoology.com", "ALEKS <Notify@ALEKS.com>",
                     "\"McGraw Hill\" <connect@mheducation.com>", "info@email.mcgrawhill.com", "realize@savvas.com",
                     "noreply@savvasrealize.com", "Google Classroom <no-reply@classroom.google.com>"] {
            check(SchoolSenders.contains(from: from), "school sender recognised: \(from)")
        }
        for from in ["promo@google.com", "x@notschoology.com", "x@schoology.com.evil.example", "schoology.com <a@evil.example>",
                     "a@schoology.com, b@evil.example", "Schoology", "", "noreply@schoology.com.", "a@b@schoology.com"] {
            check(!SchoolSenders.contains(from: from), "not a school sender: \(from)")
        }
        check(!SchoolSenders.contains(from: nil), "no From header earns no exemption")
        check(SchoolSenders.senderDomain("Teacher <t@Mail.Schoology.com>") == "mail.schoology.com", "the report label is the bare domain")

        let school = "Schoology <noreply@schoology.com>", shop = "Deals <deals@shop.example>"
        let list: [String: String] = ["list-unsubscribe": "<mailto:u@x>", "list-id": "<course.schoology.com>", "precedence": "bulk"]
        check(!AppleMailMIME.excluded(list.merging(["from": school]) { $1 }), "list and bulk headers do not force a school notice to junk")
        check(AppleMailMIME.excluded(list.merging(["from": shop]) { $1 }), "the same headers still force other senders to junk")
        check(AppleMailMIME.excluded(["from": school, "x-spam-flag": "YES"]), "an X-Spam flag still excludes a school sender")
        check(AppleMailMIME.excluded(["from": school, "precedence": "junk"]), "Precedence: junk still excludes a school sender")
        check(!AppleMailMIME.excluded(["from": school]), "a plain school notice is not excluded")

        let headers = ["from": school], other = ["from": shop]
        check(!AppleMailSource.forcedJunk(row: row(excluded: true, bulkOnly: true), headers: headers),
              "Promotions/unsubscribe metadata on a school notice is lifted; the model decides")
        check(AppleMailSource.forcedJunk(row: row(excluded: true, bulkOnly: true), headers: other),
              "the same metadata still forces other senders to junk")
        check(AppleMailSource.forcedJunk(row: row(excluded: true, bulkOnly: false), headers: headers),
              "a Junk mailbox or Mail junk level still forces a school sender to junk")
        check(!AppleMailSource.forcedJunk(row: row(excluded: false, bulkOnly: false), headers: headers),
              "an ordinary school notice is not junk")
        check(!row(excluded: false, bulkOnly: true).bulkOnly && row(excluded: true, bulkOnly: true).bulkOnly,
              "bulkOnly only describes a row that is excluded")
        print("PASS \(count) school sender exemption checks")
    }
}
'''

with tempfile.TemporaryDirectory(prefix='sentient-school-senders-') as directory:
    path = Path(directory)
    (path / 'Production.swift').write_text(PRODUCTION)
    (path / 'Tests.swift').write_text(TESTS)
    binary = path / 'test'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library',
                    '-target', f'{platform.machine()}-apple-macos15.0',
                    str(path / 'Production.swift'), str(path / 'Tests.swift'),
                    str(APP / 'Sources/AppleMailSchoolSenders.swift'), str(APP / 'Sources/AppleMailMIME.swift'),
                    '-o', str(binary)], check=True, timeout=120)
    subprocess.run([str(binary)], check=True, timeout=30)
