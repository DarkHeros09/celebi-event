-- Launcher auto-update: does the release THIS repo publishes satisfy the
-- contract the launcher actually reads?
--
-- Run from the mod directory, or from anywhere:
--
--   lua tests/launcher_update_test.lua [path/to/gen1recomp]
--
-- The engine can also come from GEN1RECOMP_ROOT.  Same discovery rules as
-- tests/celebi_event_test.lua.
--
-- ------- what this file is for
--
-- Everything else in tests/ is about the mod at runtime -- the quest, the
-- cutscene, the battle.  This one is about the other half of shipping a mod:
-- whether the launcher will offer an update for it, and whether the archive it
-- would download is the one this repo publishes.
--
-- The chain, all of it in the engine's own code:
--
--   manifest.json  ->  "github": "owner/repo"   (src/mods/Manifest.parseGithub)
--   RomImporter:_syncModUpdateInfo  ->  GET api.github.com/repos/<repo>/releases
--   ModUpdate.parseRelease          ->  semver tag + a .zip asset
--   ModUpdate.pickZipAsset          ->  prefers "<mod-id>-<version>.zip"
--   ModUpdate.statusFor             ->  "available" only if strictly newer
--   RomImporter:_modGithubAction    ->  the Update button, then the download
--
-- Each of those is asserted here against a synthetic release built to look
-- exactly like the one this repo publishes -- same tag shape, same asset
-- names, same extra assets.  The point is not that the parser works in
-- general; it is that THIS repo's shape is one the parser accepts.  A release
-- whose asset is named slightly differently, or whose tag is not semver, is
-- silently invisible in the launcher, and that failure mode is what this
-- suite exists to catch.
--
-- Nothing here touches the network.  parseReleases / pickZipAsset / statusFor
-- are pure, and they are where every one of those silent failures lives.

-- ------- locating the engine and the mod

local MOD_ROOT, ENGINE
do
  local function normalise(p)
    return (p:gsub("\\", "/"):gsub("/+$", ""))
  end
  local function isEngine(root)
    local f = io.open(root .. "/src/mods/ModUpdate.lua", "rb")
    if f then f:close() return true end
    return false
  end

  local function scriptDir()
    for i = 0, 3 do
      local a = arg and arg[i]
      if type(a) == "string" and a:match("%.lua$") then
        local d = normalise(a):match("^(.*)/[^/]+$") or "."
        if d:match("/tests$") then d = d:match("^(.*)/tests$") end
        return d, true
      end
    end
    return ".", false
  end

  local dirFromScript, sawPath = scriptDir()
  MOD_ROOT = dirFromScript
  if not io.open(MOD_ROOT .. "/manifest.json", "rb") then
    MOD_ROOT = "."
  end

  local candidates = {}
  if arg and arg[1] then candidates[#candidates + 1] = normalise(arg[1]) end
  local env = os.getenv("GEN1RECOMP_ROOT")
  if env and env ~= "" then candidates[#candidates + 1] = normalise(env) end

  local dir = MOD_ROOT
  for _ = 1, 6 do
    candidates[#candidates + 1] = dir .. "/gen1recomp"
    candidates[#candidates + 1] = dir
    local parent = dir:match("^(.*)/[^/]+$")
    if parent == nil then
      parent = "."
    elseif parent == "" then
      parent = dir:sub(1, 1) == "/" and "/" or "."
    end
    if parent == dir then break end
    dir = parent
  end
  candidates[#candidates + 1] = "."

  for _, root in ipairs(candidates) do
    if isEngine(root) then ENGINE = root break end
  end
end

if not ENGINE then
  io.stderr:write("FAIL: no gen1recomp checkout found.  Set GEN1RECOMP_ROOT " ..
    "to a tree containing src/mods/ModUpdate.lua.\n")
  os.exit(1)
end

if not io.open(MOD_ROOT .. "/manifest.json", "rb") then
  io.stderr:write("FAIL: cannot find the mod (manifest.json) from " ..
    MOD_ROOT .. "\n")
  os.exit(1)
end

package.path = ENGINE .. "/?.lua;" .. ENGINE .. "/?/init.lua;" ..
  MOD_ROOT .. "/?.lua;" .. MOD_ROOT .. "/?/init.lua;" .. package.path

-- ------- assertions

local failures, checks = 0, 0
local function ok(cond, msg)
  checks = checks + 1
  if not cond then
    failures = failures + 1
    io.write("FAIL ", msg, "\n")
  end
  return cond
end
local function eq(got, want, msg)
  return ok(got == want,
    ("%s (got %s, want %s)"):format(msg, tostring(got), tostring(want)))
end
local function neq(got, unwanted, msg)
  return ok(got ~= unwanted,
    ("%s (got %s, wanted anything else)"):format(msg, tostring(got)))
end

local function readFile(path)
  local handle = io.open(path, "rb")
  if not handle then return nil end
  local body = handle:read("*a")
  handle:close()
  return body
end

local function exists(path)
  local handle = io.open(path, "rb")
  if handle then handle:close() return true end
  return false
end

local ModUpdate = require("src.mods.ModUpdate")
local Json = require("src.link.Json")

-- ------- the manifest the launcher reads

local manifestText = readFile(MOD_ROOT .. "/manifest.json")
neq(manifestText, nil, "manifest: manifest.json is readable")
local manifest = manifestText and Json.decode(manifestText)
ok(type(manifest) == "table", "manifest: it parses as JSON")

local MOD_ID = manifest and manifest.id
local VERSION = manifest and manifest.version
ok(type(MOD_ID) == "string" and MOD_ID ~= "", "manifest: it names an id")
ok(type(VERSION) == "string" and VERSION:match("^%d+%.%d+%.%d+"),
  "manifest: the version is semver-like (" .. tostring(VERSION) .. ")")

-- The one field the whole feature hangs on.  Without it
-- RomImporter:_syncModUpdateInfo skips the mod entirely and the Update button
-- answers "This mod has no github field".
local github = manifest and manifest.github
ok(type(github) == "string" and github ~= "",
  "manifest: it carries a github field")

if type(github) == "string" then
  -- Exactly what Manifest.parseGithub accepts, so a value that passes here
  -- cannot be one the loader rejects.
  local owner, repo = github:match("^([%w%._%-]+)/([%w%._%-]+)$")
  ok(owner and repo, "manifest: github is owner/repo (" .. github .. ")")
  -- A placeholder is not an account, and a repo that does not exist 404s into
  -- a silent "no update" rather than an error, so this is a hard failure.
  eq(github:find("YOUR%-GITHUB%-USERNAME"), nil,
    "manifest: github is a real account, not the placeholder "
    .. "(fix: modkit set-github <mod> <owner>/<repo>, then rebuild)")
end

-- ------- the archive the launcher would download

-- pickZipAsset prefers "<mod-id>-<version>.zip" by exact name.  That name is
-- built from the id and version above, so a rename of either silently falls
-- back to "any .zip" -- which, in a repo that also ships platform archives,
-- means downloading the wrong file.
local expectedZip = tostring(MOD_ID) .. "-" .. tostring(VERSION) .. ".zip"
local expectedPkg = tostring(MOD_ID) .. "-" .. tostring(VERSION) .. ".modpkg"

-- The zip is deliberately NOT in the tree: it is build output, produced by CI
-- from the tagged tree and attached to the Release.  What can be checked from
-- here is that the things that build it are present, and that they derive the
-- same name this file just did.
ok(exists(MOD_ROOT .. "/.github/workflows/release.yml"),
  "build: the release workflow is in the repo")
ok(exists(MOD_ROOT .. "/tools/build_release.py"),
  "build: tools/build_release.py is vendored, so CI needs nothing local")

local workflow = readFile(MOD_ROOT .. "/.github/workflows/release.yml")
if workflow then
  neq(workflow:find("build_release.py", 1, true), nil,
    "build: the workflow calls the vendored builder")
  -- It reads the id and version out of the manifest rather than hard-coding
  -- them, so the asset name cannot drift from the manifest it ships.
  neq(workflow:find("manifest.json", 1, true), nil,
    "build: and it takes the id and version from the manifest")
  neq(workflow:find("MOD_ID", 1, true), nil,
    "build: so the asset name is built from the mod id")
end

-- The .modkitignore guard.  The tree carries no build output, but a release
-- built by hand into the repo root would otherwise be folded into the next
-- pack -- both builders walk the whole tree.  These are exact paths, so they
-- have to be renamed with the version, which is what this asserts.
local ignore = readFile(MOD_ROOT .. "/.modkitignore")
neq(ignore, nil, "build: .modkitignore is readable")
if ignore then
  for _, name in ipairs({ expectedZip, expectedPkg }) do
    neq(ignore:find("\n" .. name .. "\n", 1, true), nil,
      "build: .modkitignore guards " .. name)
  end
end

-- ------- a release shaped like ours

-- Built by hand rather than fetched, so the shape is explicit and the test
-- has no network dependency.  The decoy assets are the point: a real release
-- carries the .modpkg too, and the launcher must not pick it.
local function asset(name, size)
  return ('{"name":"%s","browser_download_url":'
    .. '"https://github.com/owner/repo/releases/download/v%s/%s",'
    .. '"size":%d,"download_count":0}'):format(name, VERSION, name, size or 1234)
end

local function releaseDoc(tag, assets, prerelease)
  local parts = {}
  for _, a in ipairs(assets) do parts[#parts + 1] = a end
  return ('{"tag_name":"%s","name":"%s","prerelease":%s,'
    .. '"body":"release notes","published_at":"2026-09-19T00:00:00Z",'
    .. '"assets":[%s]}'):format(tag, tag, tostring(prerelease == true),
      table.concat(parts, ","))
end

local function releaseList(...)
  local docs = { ... }
  return "[" .. table.concat(docs, ",") .. "]"
end

local ourAssets = {
  asset(expectedPkg, 130000),
  asset(expectedZip, 130000),
  -- A decoy that also ends in .zip.  The exact-name rule is what beats it.
  asset("another-mod-1.0.0.zip", 999),
}

local json = releaseList(releaseDoc("v" .. VERSION, ourAssets, false))
local releases, err = ModUpdate.parseReleases(json, MOD_ID)
ok(type(releases) == "table", "parse: our release list parses (" .. tostring(err) .. ")")

if type(releases) == "table" then
  eq(#releases, 1, "parse: one release survives")

  local rel = releases[1]
  eq(rel.version, VERSION, "parse: the tag strips to the manifest version")
  eq(rel.tag, "v" .. VERSION, "parse: the tag itself is kept")
  eq(rel.prerelease, false, "parse: it is not a prerelease")

  ok(type(rel.zip) == "table", "parse: a .zip asset was selected")
  if type(rel.zip) == "table" then
    eq(rel.zip.name, expectedZip,
      "parse: the EXACT <mod-id>-<version>.zip wins over the decoy")
    neq(rel.zip.name:match("%.modpkg$"), ".modpkg",
      "parse: the .modpkg is never chosen")
    eq(rel.zip.url,
      ("https://github.com/owner/repo/releases/download/v%s/%s")
        :format(VERSION, expectedZip),
      "parse: the download url is the asset's own")
  end

  -- ------- what the launcher then decides

  -- statusFor is what paints the badge.  "available" is the only status that
  -- offers a download; anything else and the Update button just re-checks.
  local status = ModUpdate.statusFor(VERSION, releases)
  eq(status, "current", "status: the released version reports current")

  local older = ModUpdate.statusFor("1.0.0", releases)
  eq(older, "available",
    "status: an older install is offered the update")

  local newer = ModUpdate.statusFor("99.0.0", releases)
  eq(newer, "current",
    "status: a newer install is never downgraded")

  -- The badge is also driven off info.best.zip.url
  -- (RomImporter:_updateAllRows), so a release with no url is invisible even
  -- when the status is right.
  local best = ModUpdate.pickBest(releases)
  ok(best and best.zip and best.zip.url, "status: best carries a zip url")
end

-- ------- the name trap this mod has and the other one does not

-- The manifest id is "celebi_event" -- with an underscore.  The repo, the mod
-- folder and every artifact built by hand so far say "celebi-event" -- with a
-- hyphen.  That is not cosmetic.  pickZipAsset compares the asset name to
-- "<mod-id>-<version>.zip" EXACTLY, and its only other rule is a lowercase
-- PREFIX match on the id; "celebi-event-1.4.6.zip" satisfies neither, so it is
-- rescued only by the last-resort "any .zip" branch, which returns whichever
-- .zip happens to come first in the release's asset array.
--
-- So the hyphenated spelling works exactly as long as the release carries one
-- zip, and silently starts downloading the wrong file the moment a second one
-- is attached.  These two assertions pin both halves, using a decoy that
-- precedes the asset in the array so the outcome is decided by the rule and
-- not by luck.
do
  local hyphenated = "celebi-event-" .. VERSION .. ".zip"
  local decoy = "zzz-other-mod.zip"

  local wrong = ModUpdate.parseReleases(releaseList(
    releaseDoc("v" .. VERSION, { asset(decoy, 1), asset(hyphenated, 2) }, false)),
    MOD_ID)
  eq(wrong and #wrong, 1, "name: a hyphenated zip is still accepted")
  eq(wrong and wrong[1] and wrong[1].zip and wrong[1].zip.name, decoy,
    "name: but '" .. hyphenated .. "' gets no special treatment, so the first "
    .. ".zip in the array wins instead")

  local right = ModUpdate.parseReleases(releaseList(
    releaseDoc("v" .. VERSION, { asset(decoy, 1), asset(expectedZip, 2) }, false)),
    MOD_ID)
  eq(right and right[1] and right[1].zip and right[1].zip.name, expectedZip,
    "name: '" .. expectedZip .. "' does win, past the same decoy")
end

-- ------- the shapes that silently fail

-- Two endpoints, two behaviours, and the difference is the whole reason this
-- section exists.
--
-- The launcher asks for the LIST (`/releases?per_page=100`, see
-- ModUpdate.apiReleasesUrl).  parseReleases takes the array branch there, and
-- an entry it cannot use is DROPPED -- no error, no reason, just a list
-- without it.  A mod whose only release is unusable therefore looks perfectly
-- up to date, which is the failure nobody notices.
--
-- The single-object branch (`/releases/latest`) is the one that answers with a
-- reason, and that reason is what the Update button puts on screen.
do
  local bad = ModUpdate.parseReleases(
    releaseList(releaseDoc("release-1", ourAssets, false)), MOD_ID)
  eq(type(bad), "table", "list: a non-semver tag does not fail the call")
  eq(bad and #bad, 0, "list: the release is dropped from it instead")

  local pkgOnly = ModUpdate.parseReleases(
    releaseList(releaseDoc("v" .. VERSION, { asset(expectedPkg, 1) }, false)),
    MOD_ID)
  eq(type(pkgOnly), "table",
    "list: a .modpkg-only release does not fail the call either")
  eq(pkgOnly and #pkgOnly, 0, "list: and it is dropped too")

  -- One bad entry must not take a good one with it: the newest release being
  -- malformed cannot hide an older, usable one.
  local mixed = ModUpdate.parseReleases(releaseList(
    releaseDoc("nightly", ourAssets, false),
    releaseDoc("v" .. VERSION, ourAssets, false)), MOD_ID)
  eq(mixed and #mixed, 1, "list: a usable release survives beside a bad one")
  eq(mixed and mixed[1] and mixed[1].version, VERSION,
    "list: and it is the one with the semver tag")

  local one, oneErr = ModUpdate.parseReleases(
    releaseDoc("release-1", ourAssets, false), MOD_ID)
  eq(one, nil, "latest: a non-semver tag is refused")
  neq(oneErr, nil, "latest: and it says why")

  local onePkg, onePkgErr = ModUpdate.parseReleases(
    releaseDoc("v" .. VERSION, { asset(expectedPkg, 1) }, false), MOD_ID)
  eq(onePkg, nil, "latest: a .modpkg-only release is refused")
  eq(onePkgErr, "latest release has no .zip asset",
    "latest: and the reason names the missing zip")
end

do
  -- A prerelease is skipped in favour of a real release, but still usable if
  -- it is all there is.  Both halves matter: publishing the update as a
  -- prerelease would otherwise hide it behind any older stable release.
  local withStable = ModUpdate.parseReleases(releaseList(
    releaseDoc("v" .. VERSION, ourAssets, false),
    releaseDoc("v99.0.0", { asset("celebi_event-99.0.0.zip", 1) }, true)
  ), MOD_ID)
  local best = withStable and ModUpdate.pickBest(withStable)
  eq(best and best.version, VERSION,
    "prerelease: a stable release outranks a newer prerelease")

  local preOnly = ModUpdate.parseReleases(
    releaseList(releaseDoc("v" .. VERSION, ourAssets, true)), MOD_ID)
  local preBest = preOnly and ModUpdate.pickBest(preOnly)
  eq(preBest and preBest.version, VERSION,
    "prerelease: a prerelease alone is still offered")
end

if failures > 0 then
  io.write(("launcher update: %d checks, %d failures\n"):format(checks, failures))
  os.exit(1)
end
io.write(("launcher update: %d checks, 0 failures\n"):format(checks))
