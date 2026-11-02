// SchoolFeedConnector.swift
// The School source in a run's connector list. Like Apple Calendar its output is a replaceable
// snapshot, not an append log, so it never uses the per-item high-water cursor and never reaches
// the on-device model: IterativeRun hands it to runSchool (IterativeRun+School.swift) before the
// engine loads, which reads the feed, replaces the School notes and the vault's School folder.
// `buckets`/`load` exist only to satisfy Connector; the generic loop never sees this connector.
// Doc: ../Documentation - Ingestion Pipeline.md

import Foundation

struct SchoolFeedConnector: Connector {
    let kind = SourceKind.schoolFeed

    func buckets(since marks: [String: ItemKey]) throws -> [Bucket] { [] }

    func load(_ item: Candidate) throws -> Artifact { Artifact(candidate: item, text: item.metadata["text"]) }
}
