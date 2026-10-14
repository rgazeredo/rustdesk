// Keep build files in a draft release; never publish them automatically.
const fs = require('node:fs')
const path = require('node:path')
const assert = require('node:assert/strict')
const repository = process.env.GITHUB_REPOSITORY
const token = process.env.GITHUB_TOKEN
assert(repository && token, 'Repository/token required')
const api = `https://api.github.com/repos/${repository}`
async function request(url, options = {}) {
  const response = await fetch(url, { ...options, headers: {
    Authorization: `Bearer ${token}`, Accept: 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28', ...options.headers
  } })
  if (!response.ok) throw new Error(`GitHub HTTP ${response.status}: ${await response.text()}`)
  return response
}
async function upload(release, file) {
  assert.equal(release.draft, true, 'Refusing to modify a public release')
  const url = release.upload_url.replace(/\{.*$/, '') + `?name=${encodeURIComponent(path.basename(file))}`
  return (await request(url, { method: 'POST', headers: { 'Content-Type': 'application/octet-stream' }, body: fs.readFileSync(file) })).json()
}
async function main() {
  const [mode, ...args] = process.argv.slice(2)
  if (mode === 'upload-bundle') {
    const version = process.env.DESKTOP_VERSION
    const product = process.env.DESKTOP_PRODUCT
    assert(/^\d+\.\d+\.\d+$/.test(version), 'Stable version required')
    assert(['setup', 'remote'].includes(product), 'Unexpected product')
    const release = await (await request(`${api}/releases`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({
      tag_name: `${product}-${version}-build-${process.env.GITHUB_RUN_ID}`,
      target_commitish: process.env.GITHUB_SHA,
      name: `AZSign ${product === 'setup' ? 'Setup' : 'Remote'} ${version} — build ${process.env.GITHUB_RUN_ID}`,
      body: 'Artefatos de compilação e validação. Rascunho; publicação separada.', draft: true
    }) })).json()
    const artifact = await upload(release, args[0])
    fs.appendFileSync(process.env.GITHUB_OUTPUT, `release_id=${release.id}\nbundle_asset_id=${artifact.id}\n`)
  } else if (mode === 'download-bundle') {
    assert(/^\d+$/.test(process.env.BUNDLE_ASSET_ID), 'Invalid asset ID')
    const response = await request(`${api}/releases/assets/${process.env.BUNDLE_ASSET_ID}`, { headers: { Accept: 'application/octet-stream' } })
    fs.writeFileSync(args[0], Buffer.from(await response.arrayBuffer()))
  } else if (mode === 'upload-results') {
    assert(/^\d+$/.test(process.env.RELEASE_ID), 'Invalid release ID')
    const release = await (await request(`${api}/releases/${process.env.RELEASE_ID}`)).json()
    for (const directory of args) {
      assert(fs.statSync(directory).isDirectory())
      for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
        if (entry.isFile() && /\.(exe|zip|sha256|txt)$/.test(entry.name)) await upload(release, path.join(directory, entry.name))
      }
    }
  } else throw new Error('Unknown artifact operation')
}
main().catch(error => { console.error(error.message); process.exitCode = 1 })
