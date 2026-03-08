import Foundation

guard CommandLine.arguments.count == 3 else {
  fputs("usage: create-finder-alias.swift <target-path> <alias-path>\n", stderr)
  exit(1)
}

let targetURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let aliasURL = URL(fileURLWithPath: CommandLine.arguments[2])

do {
  let bookmarkData = try targetURL.bookmarkData(
    options: .suitableForBookmarkFile,
    includingResourceValuesForKeys: nil,
    relativeTo: nil
  )
  try URL.writeBookmarkData(bookmarkData, to: aliasURL)
} catch {
  fputs("error: failed to create alias: \(error)\n", stderr)
  exit(1)
}
