const patchFileHeader = /^\*\*\* (?:Add|Update|Delete) File: /u

export function contentForVendorPolicy(content) {
  const lines = content.split(/\r?\n/u)
  if (!patchFileHeader.test(lines[0] ?? '')) return content

  return lines
    .slice(1)
    .filter((line) => line.startsWith('+'))
    .map((line) => line.slice(1))
    .join('\n')
}
