# Wire Hoogle MCP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Hoogle query MCP server as a Haskell cabal project and wire it, plus a rule and a sub-agent, into a new `wire-server-haskell-dev` harness.

**Architecture:** A small Haskell executable (`wire-hoogle-mcp`) with two modes: an MCP stdio server exposing one `hoogle` tool, and a `query` CLI for manual testing. Both query the Wire/general Hoogle instances over their HTTP JSON API (`?mode=json&format=text`), parse with aeson, mangle Wire nix-store `file://` doc URLs into instance-served URLs, truncate docs by default, and cache results in an `lrucache`-backed LRU. Nix builds it via `callCabal2nix` (no committed nix file, no jail) and composes it into the harness like the existing `semble` part.

**Tech Stack:** Haskell (GHC2021), cabal, `mcp-server`, `aeson`, `http-client`/`http-client-tls`, `http-types`, `optparse-applicative`, `lrucache`, `hspec`; Nix flake, `callCabal2nix`, nixwrap/openbox harness machinery.

**Spec:** `docs/superpowers/specs/2026-10-02-wire-hoogle-mcp-design.md`

## Global Constraints

- Cabal project lives at `mcps/wire-hoogle-mcp/`, one executable `wire-hoogle-mcp`.
- Library deps: `aeson`, `mcp-server`, `http-client`, `http-client-tls`, `http-types`, `optparse-applicative`, `lrucache`, `text`, `bytestring`. Test dep: `hspec`.
- No `hoogle` binary dependency. Queries go over HTTP to the instance JSON API.
- Instance URLs (env, with defaults): `WIRE_HOOGLE_URL=https://hoogle.zinfra.io`, `GENERAL_HOOGLE_URL=https://hoogle.haskell.org`, `HOOGLE_CACHE_MAX_ENTRIES=5000`.
- Mangle rule: any result URL starting with `file://` becomes `<origin>/file` + rest (the `file://` prefix replaced); everything else passes through. `origin` is the base URL of the instance actually queried.
- Docs truncation: ~500 chars; output field `docs_truncated` is `true` when truncated; `full_docs`/`--full-docs` disables it.
- One MCP tool `hoogle` with args `query` (required string), `general` (bool, default false), `count` (int, default 10), `full_docs` (bool, default false). Output is a compact JSON array; each element `{package, module, item, docs, docs_truncated, link}`.
- CLI: default (no args) runs the MCP stdio server; `query QUERY [--general] [--count N] [--full-docs]` prints the same JSON to stdout. `--help` documents everything (optparse-applicative `helper`).
- The MCP server is NOT jailed (we own and trust it).
- `rules/hoogle.md` rule + `agents/hoogle-search.md` sub-agent (`mode: subagent`, read-only), wired through the part like `semble`.
- Every part/harness/flake/check addition follows the `creating-harness-parts` skill. Verification gate: `git add -A && nix flake check` (all checks, incl. `checks.formatting`) must pass.

## File Structure

```
mcps/wire-hoogle-mcp/
  wire-hoogle-mcp.cabal       # library + exe + test-suite
  src/Wire/Hoogle/Types.hs    # Config, HoogleResult/HoogleUrl (FromJSON), HoogleEntry (ToJSON), truncateDocs, loadConfig
  src/Wire/Hoogle/Mangle.hs   # mangleLink
  src/Wire/Hoogle/Query.hs    # Server, QueryParams, QueryError, buildSearchUrl, runQuery
  src/Wire/Hoogle/Cache.hs    # HoogleCache (AtomicLRU), cacheKey, cachedQuery
  src/Wire/Hoogle/CLI.hs      # Command/QueryOptions, parseCommand, runCommand
  src/Wire/Hoogle/Server.hs   # runServer, toolList, toolCall
  app/Main.hs                 # parse command, load config, dispatch
  test/Spec.hs                # hspec aggregator
  test/TypesSpec.hs, test/MangleSpec.hs, test/QuerySpec.hs, test/CacheSpec.hs
harnesses/parts/hoogle-mcp.nix
harnesses/wire-server-haskell-dev.nix
rules/hoogle.md
agents/hoogle-search.md
flake.nix                     # callCabal2nix, toolchain devShell, harness wiring, check
```

Dependency flow: `Types` (pure) → `Mangle` (pure) → `Query` (Types+Mangle) → `Cache` (Query) → `Server`/`CLI` (Cache+Query) → `Main`.

**Key APIs used (verified):**
- `mcp-server`: `MCP.Server.runMcpServerStdio :: McpServerInfo -> McpServerHandlers IO -> IO ()`; `McpServerHandlers { prompts, resources, tools }`; `tools = Just (toolListHandler, toolCallHandler)`; `McpServerInfo { serverName, serverVersion, serverInstructions }`; `ToolDefinition { toolDefinitionName, toolDefinitionDescription, toolDefinitionInputSchema, toolDefinitionTitle }`; `InputSchemaDefinitionObject { properties, required }` with `InputSchemaDefinitionProperty { propertyType, propertyDescription }`; `Content = ContentText Text | ...`; `Error = UnknownTool | InvalidParams | InternalError | ...`. Tool/handler arg types are `Text`.
- `lrucache`: `Data.Cache.LRU.IO.newAtomicLRU :: Ord k => Maybe Integer -> IO (AtomicLRU k v)`, `insert`, `lookup` (refreshes recency), `toList`.
- `http-types`: `Network.HTTP.Types.URI.urlEncode :: Bool -> ByteString -> ByteString` (True = query mode; keeps `- . _ ~ & =` unencoded).

---

### Task 1: Cabal scaffold + local toolchain devShell

**Files:**
- Create: `mcps/wire-hoogle-mcp/wire-hoogle-mcp.cabal`
- Create: `mcps/wire-hoogle-mcp/src/Wire/Hoogle/Types.hs` (empty module for now)
- Create: `mcps/wire-hoogle-mcp/app/Main.hs` (stub)
- Create: `mcps/wire-hoogle-mcp/test/Spec.hs` (empty spec)
- Modify: `flake.nix` (toolchain devShell `devShells.wire-hoogle-mcp`)

**Interfaces:**
- Produces: a cabal project that `cabal build`/`cabal test` inside `nix develop .#wire-hoogle-mcp`; later tasks fill in `src/`, `app/Main.hs`, and the test modules.

- [ ] **Step 1: Write the cabal file**

Create `mcps/wire-hoogle-mcp/wire-hoogle-mcp.cabal`:

```cabal
cabal-version:      2.4
name:               wire-hoogle-mcp
version:            0.1.0.0
build-type:         Simple

library
  hs-source-dirs:   src
  exposed-modules:
    Wire.Hoogle.Types
  build-depends:
    base >=4.14 && <5
    , aeson >=2 && <3
    , bytestring >=0.10 && <0.13
    , http-client >=0.7 && <0.8
    , http-client-tls >=0.3 && <0.4
    , http-types >=0.12 && <0.13
    , lrucache >=1.2 && <1.3
    , mcp-server >=0.1 && <0.3
    , optparse-applicative >=0.18 && <0.19
    , text >=1.2 && <3
  default-language: GHC2021

executable wire-hoogle-mcp
  hs-source-dirs:   app
  main-is:          Main.hs
  build-depends:
    base
    , text
    , wire-hoogle-mcp
  default-language: GHC2021

test-suite spec
  type:             exitcode-stdio-1.0
  hs-source-dirs:   test
  main-is:          Spec.hs
  build-depends:
    base
    , hspec >=2 && <3
    , wire-hoogle-mcp
  default-language: GHC2021
```

Note: the library currently exposes only `Wire.Hoogle.Types`; later tasks add the rest. If a version bound excludes what nixpkgs's `haskellPackages` carries, the `nix flake check` build errors — widen the bound to the installed version.

- [ ] **Step 2: Add stub modules**

Create `mcps/wire-hoogle-mcp/src/Wire/Hoogle/Types.hs`:

```haskell
module Wire.Hoogle.Types where
```

Create `mcps/wire-hoogle-mcp/app/Main.hs`:

```haskell
module Main (main) where

main :: IO ()
main = putStrLn "wire-hoogle-mcp"
```

Create `mcps/wire-hoogle-mcp/test/Spec.hs`:

```haskell
module Main (main) where

import Test.Hspec (hspec)

main :: IO ()
main = hspec $ pure ()
```

- [ ] **Step 3: Add the toolchain devShell to flake.nix**

In `flake.nix`, inside the `let ... in` block, add next to the other harness lets:

```nix
wireHoogleMcpToolchain = pkgs.mkShell {
  packages = [
    (pkgs.haskellPackages.ghcWithPackages (ps: with ps; [
      cabal-install
      aeson
      http-client
      http-client-tls
      http-types
      hspec
      lrucache
      mcp-server
      optparse-applicative
    ]))
  ];
};
```

In the `devShells` attrset add:

```nix
devShells.wire-hoogle-mcp = wireHoogleMcpToolchain;
```

- [ ] **Step 4: Verify the toolchain builds and cabal works**

Run:

```bash
nix develop .#wire-hoogle-mcp --command cabal build --offline
nix develop .#wire-hoogle-mcp --command cabal test --offline
```

Expected: cabal builds the library + exe (downloading nothing) and the empty test suite passes.

- [ ] **Step 5: Commit**

```bash
git add mcps/wire-hoogle-mcp flake.nix
git commit -m "feat: scaffold wire-hoogle-mcp cabal project + toolchain devShell"
```

---

### Task 2: Types + Mangle (pure logic, TDD)

**Files:**
- Modify: `mcps/wire-hoogle-mcp/src/Wire/Hoogle/Types.hs`
- Create: `mcps/wire-hoogle-mcp/src/Wire/Hoogle/Mangle.hs`
- Create: `mcps/wire-hoogle-mcp/test/TypesSpec.hs`
- Create: `mcps/wire-hoogle-mcp/test/MangleSpec.hs`
- Modify: `mcps/wire-hoogle-mcp/test/Spec.hs`
- Modify: `mcps/wire-hoogle-mcp/wire-hoogle-mcp.cabal` (expose `Wire.Hoogle.Mangle`; add `test` modules + test deps `aeson`, `bytestring`, `text`)

**Interfaces:**
- Consumes: nothing (new code).
- Produces:
  - `Wire.Hoogle.Types`: `data Config = Config { cfgWireUrl :: Text, cfgGeneralUrl :: Text, cfgCacheMaxEntries :: Int }`; `loadConfig :: IO Config`; `data HoogleResult = HoogleResult { hrItem :: Text, hrDocs :: Text, hrUrl :: Maybe Text, hrPackage :: HoogleUrl, hrModule :: HoogleUrl }` with `FromJSON`; `data HoogleUrl = HoogleUrl { huName :: Maybe Text, huUrl :: Maybe Text }` with `FromJSON` (tolerates `{}`); `data HoogleEntry = HoogleEntry { hePackage :: Maybe Text, heModule :: Maybe Text, heItem :: Text, heDocs :: Text, heDocsTruncated :: Bool, heLink :: Maybe Text }` with `ToJSON`; `truncateDocs :: Int -> Text -> (Text, Bool)`.
  - `Wire.Hoogle.Mangle`: `mangleLink :: Text -> Maybe Text -> Maybe Text`.

- [ ] **Step 1: Write the failing tests**

Create `mcps/wire-hoogle-mcp/test/MangleSpec.hs`:

```haskell
module MangleSpec (spec) where

import Data.Text (Text)
import Test.Hspec (Spec, describe, it, shouldBe)
import Wire.Hoogle.Mangle (mangleLink)

origin :: Text
origin = "https://hoogle.zinfra.io"

spec :: Spec
spec = describe "mangleLink" $ do
  it "rewrites nix-store file:// URLs to the instance" $
    mangleLink origin (Just "file:///nix/store/abc-wire-api-0.1.0-doc/share/doc/wire-api-0.1.0/html/Wire-API.html#t:Conversation")
      `shouldBe` Just "https://hoogle.zinfra.io/file/nix/store/abc-wire-api-0.1.0-doc/share/doc/wire-api-0.1.0/html/Wire-API.html#t:Conversation"
  it "passes https URLs through untouched" $
    mangleLink origin (Just "https://hackage.haskell.org/package/base/docs/Prelude.html#v:map")
      `shouldBe` Just "https://hackage.haskell.org/package/base/docs/Prelude.html#v:map"
  it "passes Nothing through" $
    mangleLink origin Nothing `shouldBe` Nothing
```

Create `mcps/wire-hoogle-mcp/test/TypesSpec.hs`:

```haskell
module TypesSpec (spec) where

import qualified Data.Aeson as Aeson
import Data.Aeson (eitherDecodeStrict')
import qualified Data.ByteString as BS
import qualified Data.Text as T
import qualified Data.Text.Encoding as T
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)
import Wire.Hoogle.Types (HoogleEntry(..), HoogleResult(..), HoogleUrl(..), truncateDocs)

sampleJson :: BS.ByteString
sampleJson = T.encodeUtf8 $ T.unlines
  [ "["
  , "  {\"url\":\"https://hackage.haskell.org/package/base/docs/Prelude.html#v:map\","
  , "   \"module\":{\"url\":\"https://hackage.haskell.org/package/base/docs/Prelude.html\",\"name\":\"Prelude\"},"
  , "   \"package\":{\"url\":\"https://hackage.haskell.org/package/base\",\"name\":\"base\"},"
  , "   \"item\":\"map :: (a -> b) -> [a] -> [b]\",\"type\":\"\",\"docs\":\"map f xs is ...\"},"
  , "  {\"url\":\"file:///nix/store/h-wire-api-0.1.0-doc/share/doc/wire-api-0.1.0/html/Wire-API.html\","
  , "   \"module\":{},\"package\":{},\"item\":\"package wire-api\",\"type\":\"package\",\"docs\":\"API types\"}"
  , "]"
  ]

spec :: Spec
spec = do
  describe "FromJSON HoogleResult" $ do
    it "parses both result shapes" $ do
      let results = eitherDecodeStrict' sampleJson :: Either String [HoogleResult]
      results `shouldSatisfy` either (const False) (const True)
      let Right rs = results
      length rs `shouldBe` 2
      let r0 = head rs
      hrItem r0 `shouldBe` "map :: (a -> b) -> [a] -> [b]"
      huName (hrPackage r0) `shouldBe` Just "base"
      huName (hrModule r0) `shouldBe` Just "Prelude"
      let r1 = rs !! 1
      hrItem r1 `shouldBe` "package wire-api"
      huName (hrPackage r1) `shouldBe` Nothing
  describe "ToJSON HoogleEntry" $ do
    it "emits the documented keys incl. docs_truncated" $ do
      let entry = HoogleEntry (Just "base") (Just "Prelude") "map :: (a -> b) -> [a] -> [b]" "docs" True (Just "https://x")
          text = T.decodeUtf8 (BS.toStrict (Aeson.encode entry))
      text `shouldSatisfy` T.isInfixOf "\"docs_truncated\":true"
      text `shouldSatisfy` T.isInfixOf "\"link\":\"https://x\""
  describe "truncateDocs" $ do
    it "leaves short docs untruncated" $
      truncateDocs 10 "short" `shouldBe` ("short", False)
    it "truncates long docs and flags it" $
      truncateDocs 10 (T.replicate 20 "x") `shouldBe` (T.replicate 10 "x", True)
```

- [ ] **Step 2: Update Spec.hs to aggregate the new modules**

Replace `mcps/wire-hoogle-mcp/test/Spec.hs` with:

```haskell
module Main (main) where

import Test.Hspec (hspec)

import qualified MangleSpec
import qualified TypesSpec

main :: IO ()
main = hspec $ do
  MangleSpec.spec
  TypesSpec.spec
```

- [ ] **Step 3: Update the cabal file**

In `wire-hoogle-mcp.cabal`: add `Wire.Hoogle.Mangle` to the library `exposed-modules`; extend the test-suite with:

```cabal
  other-modules:
    MangleSpec
    TypesSpec
  build-depends:
    base
    , aeson
    , bytestring
    , hspec
    , text
    , wire-hoogle-mcp
```

- [ ] **Step 4: Run the tests to verify they fail**

Run: `nix develop .#wire-hoogle-mcp --command cabal test --offline`
Expected: FAIL — `Could not find module 'Wire.Hoogle.Mangle'` (and `Types` is an empty module).

- [ ] **Step 5: Implement `Wire.Hoogle.Mangle`**

Create `mcps/wire-hoogle-mcp/src/Wire/Hoogle/Mangle.hs`:

```haskell
module Wire.Hoogle.Mangle (mangleLink) where

import Data.Text (Text)
import qualified Data.Text as T

-- | Rewrite a docs URL for the instance actually queried: nix-store file://
-- URLs are served by the instance under <origin>/file/...; other URLs pass
-- through unchanged.
mangleLink :: Text -> Maybe Text -> Maybe Text
mangleLink origin (Just url)
  | "file://" `T.isPrefixOf` url = Just (origin <> "/file" <> T.drop 7 url)
  | otherwise = Just url
mangleLink _ Nothing = Nothing
```

- [ ] **Step 6: Implement `Wire.Hoogle.Types`**

Replace `mcps/wire-hoogle-mcp/src/Wire/Hoogle/Types.hs`:

```haskell
module Wire.Hoogle.Types
  ( Config(..)
  , loadConfig
  , HoogleEntry(..)
  , HoogleResult(..)
  , HoogleUrl(..)
  , truncateDocs
  ) where

import Data.Aeson (FromJSON(..), ToJSON(..), object, withObject, (.:), (.:?), (.!=), (.=))
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import System.Environment (lookupEnv)
import Text.Read (readMaybe)

data Config = Config
  { cfgWireUrl :: Text
  , cfgGeneralUrl :: Text
  , cfgCacheMaxEntries :: Int
  }
  deriving (Eq, Show)

defaultWireUrl :: Text
defaultWireUrl = "https://hoogle.zinfra.io"

defaultGeneralUrl :: Text
defaultGeneralUrl = "https://hoogle.haskell.org"

defaultCacheMaxEntries :: Int
defaultCacheMaxEntries = 5000

loadConfig :: IO Config
loadConfig = do
  wireUrl <- envOr "WIRE_HOOGLE_URL" defaultWireUrl
  generalUrl <- envOr "GENERAL_HOOGLE_URL" defaultGeneralUrl
  cacheMax <- envIntOr "HOOGLE_CACHE_MAX_ENTRIES" defaultCacheMaxEntries
  pure (Config wireUrl generalUrl cacheMax)
  where
    envOr :: String -> Text -> IO Text
    envOr name def = maybe def T.pack <$> lookupEnv name
    envIntOr :: String -> Int -> IO Int
    envIntOr name def = do
      v <- lookupEnv name
      pure (maybe def (fromMaybe def . readMaybe) v)

data HoogleUrl = HoogleUrl { huName :: Maybe Text, huUrl :: Maybe Text }
  deriving (Eq, Show)

instance FromJSON HoogleUrl where
  parseJSON = withObject "HoogleUrl" $ \o ->
    HoogleUrl <$> o .:? "name" <*> o .:? "url"

data HoogleResult = HoogleResult
  { hrItem :: Text
  , hrDocs :: Text
  , hrUrl :: Maybe Text
  , hrPackage :: HoogleUrl
  , hrModule :: HoogleUrl
  }
  deriving (Eq, Show)

instance FromJSON HoogleResult where
  parseJSON = withObject "HoogleResult" $ \o ->
    HoogleResult
      <$> o .: "item"
      <*> o .:? "docs" .!= ""
      <*> o .:? "url"
      <*> o .:? "package" .!= HoogleUrl Nothing Nothing
      <*> o .:? "module" .!= HoogleUrl Nothing Nothing

data HoogleEntry = HoogleEntry
  { hePackage :: Maybe Text
  , heModule :: Maybe Text
  , heItem :: Text
  , heDocs :: Text
  , heDocsTruncated :: Bool
  , heLink :: Maybe Text
  }
  deriving (Eq, Show)

instance ToJSON HoogleEntry where
  toJSON e = object
    [ "package" .= hePackage e
    , "module" .= heModule e
    , "item" .= heItem e
    , "docs" .= heDocs e
    , "docs_truncated" .= heDocsTruncated e
    , "link" .= heLink e
    ]

truncateDocs :: Int -> Text -> (Text, Bool)
truncateDocs limit docs
  | T.length docs <= limit = (docs, False)
  | otherwise = (T.take limit docs, True)
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `nix develop .#wire-hoogle-mcp --command cabal test --offline`
Expected: PASS (both specs green).

- [ ] **Step 8: Commit**

```bash
git add mcps/wire-hoogle-mcp
git commit -m "feat: hoogle result types, URL mangling, docs truncation"
```

---

### Task 3: Query + Cache (HTTP + LRU, TDD)

**Files:**
- Create: `mcps/wire-hoogle-mcp/src/Wire/Hoogle/Query.hs`
- Create: `mcps/wire-hoogle-mcp/src/Wire/Hoogle/Cache.hs`
- Create: `mcps/wire-hoogle-mcp/test/QuerySpec.hs`
- Create: `mcps/wire-hoogle-mcp/test/CacheSpec.hs`
- Modify: `mcps/wire-hoogle-mcp/test/Spec.hs`
- Modify: `mcps/wire-hoogle-mcp/wire-hoogle-mcp.cabal` (expose both modules; add test modules; add `lrucache` to test-suite deps)

**Interfaces:**
- Consumes: `Wire.Hoogle.Types` (`Config(..)`, `HoogleEntry(..)`, `HoogleResult(..)`, `truncateDocs`), `Wire.Hoogle.Mangle` (`mangleLink`).
- Produces:
  - `Wire.Hoogle.Query`: `data Server = WireServer | GeneralServer`; `data QueryParams = QueryParams { qpQuery :: Text, qpCount :: Int, qpFullDocs :: Bool }`; `data QueryError = QueryHttp HttpException | QueryBadStatus Int | QueryParse String` (`Show`); `serverUrl :: Config -> Server -> Text`; `buildSearchUrl :: Text -> Text -> Int -> Text`; `runQuery :: Manager -> Config -> Server -> QueryParams -> IO (Either QueryError [HoogleEntry])`.
  - `Wire.Hoogle.Cache`: `type HoogleCache = AtomicLRU Text [HoogleEntry]`; `newHoogleCache :: Int -> IO HoogleCache`; `cacheKey :: Server -> QueryParams -> Text`; `cachedQuery :: Manager -> HoogleCache -> Config -> Server -> QueryParams -> IO (Either QueryError [HoogleEntry])`.

- [ ] **Step 1: Write the failing tests**

Create `mcps/wire-hoogle-mcp/test/QuerySpec.hs`:

```haskell
module QuerySpec (spec) where

import Test.Hspec (Spec, describe, it, shouldBe)
import Wire.Hoogle.Query (buildSearchUrl)

spec :: Spec
spec = describe "buildSearchUrl" $ do
  it "url-encodes the query and appends count" $
    buildSearchUrl "https://hoogle.zinfra.io" "a -> b" 10
      `shouldBe` "https://hoogle.zinfra.io?mode=json&format=text&hoogle=a%20->%20b&count=10"
```

Create `mcps/wire-hoogle-mcp/test/CacheSpec.hs`:

```haskell
module CacheSpec (spec) where

import Data.Cache.LRU.IO (AtomicLRU, insert, lookup, newAtomicLRU, toList)
import qualified Data.Map.Strict as Map
import Test.Hspec (Spec, describe, it, shouldBe)

spec :: Spec
spec = describe "AtomicLRU (lrucache)" $ do
  it "evicts the least-recently-used entries at capacity" $ do
    cache <- newAtomicLRU (Just 2) :: IO (AtomicLRU Int Int)
    insert 1 1 cache
    insert 2 2 cache
    insert 3 3 cache
    entries <- toList cache
    Map.fromList entries `shouldBe` Map.fromList [(2, 2), (3, 3)]
  it "refreshes recency on lookup" $ do
    cache <- newAtomicLRU (Just 2) :: IO (AtomicLRU Int Int)
    insert 1 1 cache
    insert 2 2 cache
    _ <- lookup 1 cache
    insert 3 3 cache
    entries <- toList cache
    Map.fromList entries `shouldBe` Map.fromList [(1, 1), (3, 3)]
```

- [ ] **Step 2: Update Spec.hs and the cabal file**

Append `QuerySpec`/`CacheSpec` imports to `Spec.hs` and add them to the aggregate; add the two modules to `other-modules` and `lrucache` to the test-suite `build-depends`. Add `Wire.Hoogle.Query` and `Wire.Hoogle.Cache` to the library `exposed-modules`.

- [ ] **Step 3: Run the tests to verify they fail**

Run: `nix develop .#wire-hoogle-mcp --command cabal test --offline`
Expected: FAIL — `Could not find module 'Wire.Hoogle.Query'` / `Wire.Hoogle.Cache`.

- [ ] **Step 4: Implement `Wire.Hoogle.Query`**

Create `mcps/wire-hoogle-mcp/src/Wire/Hoogle/Query.hs`:

```haskell
module Wire.Hoogle.Query
  ( Server(..)
  , QueryParams(..)
  , QueryError(..)
  , serverUrl
  , buildSearchUrl
  , runQuery
  ) where

import Control.Exception (HttpException, try)
import Data.Aeson (eitherDecode)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as BL
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as T
import qualified Data.Text.Encoding.Error as T
import Network.HTTP.Client (Manager, Request, httpLbs, parseRequest, responseStatus)
import Network.HTTP.Types (statusCode)
import Network.HTTP.Types.URI (urlEncode)
import Wire.Hoogle.Mangle (mangleLink)
import Wire.Hoogle.Types (Config(..), HoogleEntry(..), HoogleResult(..), truncateDocs)

data Server = WireServer | GeneralServer
  deriving (Eq, Show)

data QueryParams = QueryParams
  { qpQuery :: Text
  , qpCount :: Int
  , qpFullDocs :: Bool
  }
  deriving (Eq, Show)

data QueryError
  = QueryHttp HttpException
  | QueryBadStatus Int
  | QueryParse String
  deriving (Show)

serverUrl :: Config -> Server -> Text
serverUrl cfg WireServer = cfgWireUrl cfg
serverUrl cfg GeneralServer = cfgGeneralUrl cfg

buildSearchUrl :: Text -> Text -> Int -> Text
buildSearchUrl base query count =
  base
    <> "?mode=json&format=text&hoogle="
    <> T.decodeUtf8With T.lenientDecode (urlEncode True (T.encodeUtf8 query))
    <> "&count="
    <> T.pack (show count)

runQuery :: Manager -> Config -> Server -> QueryParams -> IO (Either QueryError [HoogleEntry])
runQuery mgr cfg server qp = do
  let origin = serverUrl cfg server
      url = buildSearchUrl origin (qpQuery qp) (qpCount qp)
  response <- try (httpLbs (parseRequestStrict url) mgr)
  pure $ case response of
    Left e -> Left (QueryHttp e)
    Right resp
      | statusCode (responseStatus resp) /= 200 ->
          Left (QueryBadStatus (statusCode (responseStatus resp)))
      | otherwise -> case eitherDecode (responseBody resp) of
          Left e -> Left (QueryParse e)
          Right results -> Right (map (toEntry origin (qpFullDocs qp)) results)
  where
    parseRequestStrict :: Text -> Request
    parseRequestStrict u =
      case parseRequest (T.encodeUtf8 u) of
        Left e -> error ("invalid hoogle URL: " ++ show e)
        Right r -> r

toEntry :: Text -> Bool -> HoogleResult -> HoogleEntry
toEntry origin fullDocs r = HoogleEntry
  { hePackage = huName (hrPackage r)
  , heModule = huName (hrModule r)
  , heItem = hrItem r
  , heDocs = docs
  , heDocsTruncated = truncated
  , heLink = mangleLink origin (hrUrl r)
  }
  where
    (docs, truncated) =
      if fullDocs then (hrDocs r, False) else truncateDocs 500 (hrDocs r)
```

(`huName` is exported from `Wire.Hoogle.Types`.)

- [ ] **Step 5: Implement `Wire.Hoogle.Cache`**

Create `mcps/wire-hoogle-mcp/src/Wire/Hoogle/Cache.hs`:

```haskell
module Wire.Hoogle.Cache
  ( HoogleCache
  , newHoogleCache
  , cacheKey
  , cachedQuery
  ) where

import Data.Cache.LRU.IO (AtomicLRU, insert, lookup, newAtomicLRU)
import Data.Text (Text)
import qualified Data.Text as T
import Network.HTTP.Client (Manager)
import Wire.Hoogle.Query (QueryError, QueryParams(..), Server(..), runQuery)
import Wire.Hoogle.Types (Config, HoogleEntry)

type HoogleCache = AtomicLRU Text [HoogleEntry]

newHoogleCache :: Int -> IO HoogleCache
newHoogleCache capacity = newAtomicLRU (Just (fromIntegral capacity))

cacheKey :: Server -> QueryParams -> Text
cacheKey server qp =
  serverName <> "\0" <> qpQuery qp <> "\0"
    <> T.pack (show (qpCount qp)) <> "\0" <> T.pack (show (qpFullDocs qp))
  where
    serverName = case server of
      WireServer -> "wire"
      GeneralServer -> "general"

cachedQuery :: Manager -> HoogleCache -> Config -> Server -> QueryParams -> IO (Either QueryError [HoogleEntry])
cachedQuery mgr cache cfg server qp = do
  hit <- lookup key cache
  case hit of
    Just entries -> pure (Right entries)
    Nothing -> do
      result <- runQuery mgr cfg server qp
      case result of
        Right entries -> insert key entries cache >> pure (Right entries)
        Left err -> pure (Left err)
  where
    key = cacheKey server qp
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `nix develop .#wire-hoogle-mcp --command cabal test --offline`
Expected: PASS (all four specs green).

- [ ] **Step 7: Commit**

```bash
git add mcps/wire-hoogle-mcp
git commit -m "feat: hoogle HTTP query + lrucache-backed cached query"
```

---

### Task 4: Server + CLI + Main (MCP tool and query command)

**Files:**
- Create: `mcps/wire-hoogle-mcp/src/Wire/Hoogle/Server.hs`
- Create: `mcps/wire-hoogle-mcp/src/Wire/Hoogle/CLI.hs`
- Replace: `mcps/wire-hoogle-mcp/app/Main.hs`
- Modify: `mcps/wire-hoogle-mcp/wire-hoogle-mcp.cabal` (expose `Wire.Hoogle.Server`, `Wire.Hoogle.CLI`)

**Interfaces:**
- Consumes: `Wire.Hoogle.Cache` (`HoogleCache`, `newHoogleCache`, `cachedQuery`), `Wire.Hoogle.Query` (`QueryParams(..)`, `Server(..)`), `Wire.Hoogle.Types` (`Config(..)`, `loadConfig`).
- Produces:
  - `Wire.Hoogle.Server`: `runServer :: Config -> IO ()`.
  - `Wire.Hoogle.CLI`: `data Command = CommandServe | CommandQuery QueryOptions`; `data QueryOptions = QueryOptions { qoQuery :: Text, qoCount :: Int, qoFullDocs :: Bool, qoServer :: Maybe Server }`; `parseCommand :: IO Command`; `runCommand :: Command -> Config -> IO ()`.

- [ ] **Step 1: Implement `Wire.Hoogle.Server`**

Create `mcps/wire-hoogle-mcp/src/Wire/Hoogle/Server.hs`:

```haskell
module Wire.Hoogle.Server (runServer) where

import qualified Data.Aeson as Aeson (encode)
import qualified Data.ByteString.Lazy.Char8 as BL8
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as T
import Data.Text.Read (decimal)
import MCP.Server
  ( Content(..)
  , Error(..)
  , InputSchemaDefinition(..)
  , InputSchemaDefinitionProperty(..)
  , McpServerHandlers(..)
  , McpServerInfo(..)
  , ToolDefinition(..)
  , runMcpServerStdio
  )
import Network.HTTP.Client (Manager, newManager)
import Network.HTTP.Client.TLS (tlsManagerSettings)
import Wire.Hoogle.Cache (HoogleCache, cachedQuery, newHoogleCache)
import Wire.Hoogle.Query (QueryParams(..), Server(..))
import Wire.Hoogle.Types (Config(..))

runServer :: Config -> IO ()
runServer cfg = do
  manager <- newManager tlsManagerSettings
  cache <- newHoogleCache (cfgCacheMaxEntries cfg)
  let serverInfo = McpServerInfo
        { serverName = "wire-hoogle"
        , serverVersion = "0.1.0.0"
        , serverInstructions =
            "Provides the 'hoogle' tool for Haskell API lookup. It queries the \
            \Wire Hoogle instance by default and the general instance only when \
            \'general' is set (packages not yet in the project). 'query' is a \
            \Hoogle query, not a plain search: see the tool description."
        }
      handlers = McpServerHandlers
        { prompts = Nothing
        , resources = Nothing
        , tools = Just (toolList, toolCall manager cache cfg)
        }
  runMcpServerStdio serverInfo handlers

toolList :: IO [ToolDefinition]
toolList = pure
  [ ToolDefinition
      { toolDefinitionName = "hoogle"
      , toolDefinitionDescription =
          "Search Haskell API documentation with Hoogle. 'query' is a Hoogle \
          \query, NOT a plain text search. It supports type signatures \
          \('a -> a', 'Text -> IO ()'), names ('map'), combined \
          \'name :: type' ('readFile :: FilePath -> IO String'), and scope \
          \filters ('+pkg'/'+Package' restrict to packages, '-pkg' excludes, \
          \'+Module' restricts to modules; '::' forces type-only search). The \
          \Wire Hoogle instance (default) indexes the project's packages; set \
          \'general' to true ONLY for a package not yet in the project (rare). \
          \Results are JSON: package, module, signature, docs."
      , toolDefinitionInputSchema = InputSchemaDefinitionObject
          { properties =
              [ ("query", InputSchemaDefinitionProperty "string" "Hoogle query, not a plain search (see syntax in the tool description)")
              , ("general", InputSchemaDefinitionProperty "boolean" "Search the general hoogle instance (hoogle.haskell.org) instead of Wire; only for packages not yet in the project")
              , ("count", InputSchemaDefinitionProperty "integer" "Maximum number of results (default: 10)")
              , ("full_docs", InputSchemaDefinitionProperty "boolean" "Return full docs instead of truncating to ~500 chars")
              ]
          , required = [ "query" ]
          }
      , toolDefinitionTitle = Nothing
      }
  ]

toolCall :: Manager -> HoogleCache -> Config -> Text -> [(Text, Text)] -> IO (Either Error Content)
toolCall manager cache cfg toolName args
  | toolName /= "hoogle" = pure (Left (UnknownTool toolName))
  | otherwise =
      case lookup "query" args of
        Nothing -> pure (Left (InvalidParams "missing required argument 'query'"))
        Just query ->
          let qp = QueryParams
                { qpQuery = query
                , qpCount = fromMaybe 10 (readInt =<< lookup "count" args)
                , qpFullDocs = lookup "full_docs" args == Just "true"
                }
              server = if lookup "general" args == Just "true" then GeneralServer else WireServer
          in do
            result <- cachedQuery manager cache cfg server qp
            pure (case result of
              Left err -> Left (InternalError (T.pack (show err)))
              Right entries -> Right (ContentText (T.decodeUtf8 (BL8.toStrict (Aeson.encode entries))))
            )
  where
    readInt :: Text -> Maybe Int
    readInt t = case decimal t of
      Right (n, rest) | T.null rest -> Just n
      _ -> Nothing
```

Note: `ToolName`/`ArgumentName`/`ArgumentValue` are `Text`, so `Text -> [(Text, Text)]` matches `ToolCallHandler`.

- [ ] **Step 2: Implement `Wire.Hoogle.CLI`**

Create `mcps/wire-hoogle-mcp/src/Wire/Hoogle/CLI.hs`:

```haskell
module Wire.Hoogle.CLI
  ( Command(..)
  , QueryOptions(..)
  , parseCommand
  , runCommand
  ) where

import Data.Aeson (encode)
import qualified Data.ByteString.Lazy as BL
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as T
import qualified Data.Text.IO as TIO
import Network.HTTP.Client (newManager)
import Network.HTTP.Client.TLS (tlsManagerSettings)
import Options.Applicative
  ( Parser
  , command
  , execParser
  , flag
  , fullDesc
  , header
  , help
  , helper
  , hsubparser
  , info
  , long
  , metavar
  , option
  , progDesc
  , short
  , strArgument
  , switch
  , value
  )
import System.Exit (exitFailure)
import System.IO (stderr)
import Wire.Hoogle.Cache (cachedQuery, newHoogleCache)
import Wire.Hoogle.Query (QueryParams(..), Server(..))
import Wire.Hoogle.Server (runServer)
import Wire.Hoogle.Types (Config(..))

data QueryOptions = QueryOptions
  { qoQuery :: Text
  , qoCount :: Int
  , qoFullDocs :: Bool
  , qoServer :: Maybe Server
  }
  deriving (Eq, Show)

data Command = CommandServe | CommandQuery QueryOptions
  deriving (Eq, Show)

queryParser :: Parser QueryOptions
queryParser = QueryOptions
  <$> (T.pack <$> strArgument (metavar "QUERY" <> help "Hoogle query, not a plain search (see --help)"))
  <*> option auto (long "count" <> short 'n' <> value 10 <> metavar "N" <> help "Maximum number of results (default: 10)")
  <*> switch (long "full-docs" <> help "Return full docs instead of truncating to ~500 chars")
  <*> (flag Nothing (Just WireServer) (long "general" <> help "Search the general hoogle instance (hoogle.haskell.org) instead of Wire"))

commandParser :: Parser Command
commandParser =
  (pure CommandServe)
    <|> hsubparser
      ( command "query"
          ( info queryParser
              ( progDesc "Query hoogle and print the mangled JSON results to stdout"
              )
          )
      )

parseCommand :: IO Command
parseCommand =
  execParser
    ( info
        (helper <*> commandParser)
        ( fullDesc
            <> progDesc "Hoogle MCP server (default) or hoogle query CLI"
            <> header "wire-hoogle-mcp"
        )
    )

runCommand :: Command -> Config -> IO ()
runCommand CommandServe cfg = runServer cfg
runCommand (CommandQuery qo) cfg = do
  manager <- newManager tlsManagerSettings
  cache <- newHoogleCache (cfgCacheMaxEntries cfg)
  let server = fromMaybe WireServer (qoServer qo)
      qp = QueryParams (qoQuery qo) (qoCount qo) (qoFullDocs qo)
  result <- cachedQuery manager cache cfg server qp
  case result of
    Left err -> TIO.hPutStrLn stderr ("error: " <> T.pack (show err)) >> exitFailure
    Right entries -> TIO.putStrLn (T.decodeUtf8 (toStrict (encode entries)))
  where
    toStrict = BL.toStrict
```

`TIO.putStrLn` needs a `Text`; `encode` gives a lazy `BL.ByteString`, so `T.decodeUtf8 (BL.toStrict (encode entries))` converts. Import `qualified Data.ByteString.Lazy as BL` and `System.IO (stderr)`.

- [ ] **Step 3: Replace `app/Main.hs`**

```haskell
module Main (main) where

import Wire.Hoogle.CLI (parseCommand, runCommand)
import Wire.Hoogle.Types (loadConfig)

main :: IO ()
main = do
  command <- parseCommand
  config <- loadConfig
  runCommand command config
```

- [ ] **Step 4: Update the cabal file**

Add `Wire.Hoogle.Server` and `Wire.Hoogle.CLI` to the library `exposed-modules`. The executable already depends on `wire-hoogle-mcp` and `base`; it now needs `text` for the `Text` types used via the lib — `text` is already a dependency of the library, and the executable's `build-depends` already lists `text`.

- [ ] **Step 5: Build and run the CLI to verify end-to-end**

Run:

```bash
nix develop .#wire-hoogle-mcp --command cabal build --offline
nix develop .#wire-hoogle-mcp --command cabal run --offline wire-hoogle-mcp -- query "map :: (a -> b) -> [a] -> [b]" --count 3
```

Expected: prints a JSON array of results with `package`/`module`/`item`/`docs`/`docs_truncated`/`link` keys; the Wire links start with `https://hoogle.zinfra.io/file/nix/store/...`.

Also verify: `nix develop .#wire-hoogle-mcp --command cabal run --offline wire-hoogle-mcp -- --help` shows the `query` subcommand and all options; and `cabal run ... -- query "map" --general --count 2` returns hackage links.

- [ ] **Step 6: Run the test suite**

Run: `nix develop .#wire-hoogle-mcp --command cabal test --offline`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add mcps/wire-hoogle-mcp
git commit -m "feat: mcp server tool + query cli for wire-hoogle-mcp"
```

---

### Task 5: Nix integration (part, rule, agent, harness, flake wiring)

**Files:**
- Create: `harnesses/parts/hoogle-mcp.nix`
- Create: `harnesses/wire-server-haskell-dev.nix`
- Create: `rules/hoogle.md`
- Create: `agents/hoogle-search.md`
- Modify: `flake.nix`

**Interfaces:**
- Consumes: `wireHoogleMcp` derivation (from `callCabal2nix`, produced in this task); harnessLib from `lib/`; `enrichWithLLMaaS`.
- Produces: `harnesses/wire-server-haskell-dev.nix` returning `{ package, devShell, llmaas = { package, devShell } }`; flake attrs `packages.wire-server-haskell-dev`, `packages.wire-server-haskell-dev-llmaas`, `packages.wire-hoogle-mcp`, `devShells.wire-server-haskell-dev`, `devShells.wire-server-haskell-dev-llmaas`; part module `harnesses/parts/hoogle-mcp.nix` (function of `{ wireHoogleMcp }`).

- [ ] **Step 1: Create the part**

Create `harnesses/parts/hoogle-mcp.nix`:

```nix
{ wireHoogleMcp }:
{
  config.opencode.mcp["wire-hoogle"] = {
    type = "local";
    command = [ "${wireHoogleMcp}/bin/wire-hoogle-mcp" ];
    environment = {
      WIRE_HOOGLE_URL = "https://hoogle.zinfra.io";
      GENERAL_HOOGLE_URL = "https://hoogle.haskell.org";
    };
  };
  config.rules = [ ./../../rules/hoogle.md ];
  config.agents = [ ./../../agents/hoogle-search.md ];
  config.dependencies = [ wireHoogleMcp ];
}
```

- [ ] **Step 2: Create the rule**

Create `rules/hoogle.md`:

```markdown
# Haskell API Search (Hoogle)

Use the `hoogle` MCP tool to look up Haskell library APIs — function names,
types, and documentation — instead of guessing or grepping. It covers what LSP
servers don't: functions in dependencies that the project doesn't use yet.

- The `query` is a Hoogle query, NOT a plain search. Bare text (`map`) searches
  names; `a -> a` searches types; `map :: (a -> b) -> [a] -> [b]` combines
  both; `+pkg` / `-pkg` restrict packages; `+Module` restricts modules.
- Default instance is Wire Hoogle (all packages used by the target project).
- Set `general` to true ONLY when looking for a package not yet part of the
  project — this is rare.
- Results are structured JSON: package, module, signature (`item`), docs, and
  a docs link.
```

- [ ] **Step 3: Create the sub-agent**

Create `agents/hoogle-search.md`:

```markdown
---
name: hoogle-search
description: Haskell API search agent. Use for looking up library functions, types, and signatures by name or type via Hoogle, especially for packages the project doesn't use yet.
mode: subagent
permission:
  read: allow
---

Use the `hoogle` MCP tool to answer Haskell API questions.

1. Translate the question into a Hoogle query. `query` is NOT a plain search:
   use a type signature (`a -> a`), a name (`map`), or combined
   `name :: type`. Add `+pkg`/`-pkg` scope filters when useful.
2. Default to the Wire Hoogle instance (covers the project's packages). Set
   `general` to true only for a dependency not yet in the project.
3. Keep results lean: the default `count=10` and truncated docs are usually
   enough; request `full_docs` only when the signature is unclear.
4. Report the matched package, module, and signature; quote the docs when they
   answer the question directly.
```

- [ ] **Step 4: Create the harness**

Create `harnesses/wire-server-haskell-dev.nix`:

```nix
{
  lib,
  pkgs,
  nixwrap,
  opencode,
  agent-skills,
  superpowers,
  wireHoogleMcp,
}:
let
  harnessLib = import ../lib {
    inherit
      lib
      pkgs
      nixwrap
      opencode
      ;
  };
  modules = [
    (import ./parts/base.nix { inherit lib; })
    (import ./parts/superpowers.nix {
      inherit
        pkgs
        agent-skills
        superpowers
        ;
    })
    (import ./parts/hoogle-mcp.nix { inherit wireHoogleMcp; })
    (import ./parts/be-concise.nix)
  ];
  harness = harnessLib.mkHarness {
    name = "wire-server-haskell-dev";
    inherit modules;
  };
  llmaasHarness = harnessLib.enrichWithLLMaaS {
    name = "wire-server-haskell-dev";
    inherit modules;
  };
in
{
  inherit (harness) package devShell;
  llmaas = {
    inherit (llmaasHarness) package devShell;
  };
}
```

- [ ] **Step 5: Wire flake.nix**

Add to the `let` block (near `semble`/`vanillaDevHarness`):

```nix
wireHoogleMcp = pkgs.haskellPackages.callCabal2nix "wire-hoogle-mcp" ./mcps/wire-hoogle-mcp (drv: drv // { doCheck = true; });
wireServerHaskellDevHarness = import ./harnesses/wire-server-haskell-dev.nix {
  inherit
    lib
    pkgs
    nixwrap
    opencode
    agent-skills
    superpowers
    wireHoogleMcp
    ;
};
```

In `packages` add:

```nix
packages.wire-hoogle-mcp = wireHoogleMcp;
packages.wire-server-haskell-dev = wireServerHaskellDevHarness.package;
packages.wire-server-haskell-dev-llmaas = wireServerHaskellDevHarness.llmaas.package;
```

In `devShells` add:

```nix
devShells.wire-server-haskell-dev = wireServerHaskellDevHarness.devShell;
devShells.wire-server-haskell-dev-llmaas = wireServerHaskellDevHarness.llmaas.devShell;
```

- [ ] **Step 6: Build the harness and run the MCP CLI from the built package**

Run:

```bash
nix build .#wire-server-haskell-dev
nix run .#wire-hoogle-mcp -- query "a -> a" --count 3
```

Expected: the harness builds (which builds `wireHoogleMcp` and runs its test suite in the check phase — the hspec suite must pass); the `nix run` prints a JSON array (hackage links, since no `--general` and this uses the Wire instance default).

- [ ] **Step 7: Commit**

```bash
git add harnesses rules agents flake.nix
git commit -m "feat: wire-server-haskell-dev harness with hoogle mcp part"
```

---

### Task 6: flake check for wire-server-haskell-dev

**Files:**
- Modify: `flake.nix` (add `checks.wire-server-haskell-dev`)

**Interfaces:**
- Consumes: `wireServerHaskellDevHarness.package`, `wireHoogleMcp`, `resolv` (the `run()` bwrap helper pattern from the existing checks).

- [ ] **Step 1: Add the check**

Copy the `vanilla-dev` check's `run()` + `resolv` bwrap scaffolding into a new check. In `flake.nix` `checks` add:

```nix
wire-server-haskell-dev =
  pkgs.runCommand "check-wire-server-haskell-dev"
    {
      nativeBuildInputs = [
        pkgs.bubblewrap
        pkgs.coreutils
        pkgs.bash
        pkgs.jq
        wireServerHaskellDevHarness.package
      ];
      inherit resolv wireHoogleMcp;
    }
    ''
      set -euo pipefail
      export HOME=$TMPDIR; mkdir -p $HOME

      run() {
        bwrap \
          --die-with-parent \
          --tmpfs / \
          --ro-bind /nix /nix \
          --dir /bin \
          --ro-bind /bin/sh /bin/sh \
          --dir /usr/bin \
          --ro-bind ${pkgs.coreutils}/bin/env /usr/bin/env \
          --ro-bind /etc/passwd /etc/passwd \
          --ro-bind /etc/group /etc/group \
          --ro-bind /etc/hosts /etc/hosts \
          --dir /etc/ssl --dir /etc/static/ssl \
          --ro-bind $resolv /etc/resolv.conf \
          --dir /tmp \
          --proc /proc --dev /dev \
          --bind $TMPDIR $TMPDIR \
          --setenv HOME $TMPDIR \
          --setenv PATH ${
            lib.makeBinPath [
              pkgs.bubblewrap
              pkgs.coreutils
              pkgs.bash
            ]
          } \
          --chdir $TMPDIR \
          -- "$@"
      }

      run ${wireServerHaskellDevHarness.package}/bin/opencode debug config > config.json
      jq -e '.permission.edit == "ask"' config.json >/dev/null
      jq -e '.mcp["wire-hoogle"].type == "local"' config.json >/dev/null
      jq -e --arg cmd "${wireHoogleMcp}/bin/wire-hoogle-mcp" \
        'any(.mcp["wire-hoogle"].command[]; . == $cmd)' config.json >/dev/null
      jq -e '.mcp["wire-hoogle"].environment.WIRE_HOOGLE_URL == "https://hoogle.zinfra.io"' config.json >/dev/null
      jq -e 'any(.instructions[]; endswith("rules/hoogle.md"))' config.json >/dev/null
      jq -e '.agent | has("hoogle-search")' config.json >/dev/null

      run ${wireServerHaskellDevHarness.package}/bin/opencode debug skill > skills.json
      jq -e 'any(.[]; .name == "brainstorming")' skills.json >/dev/null

      run ${wireServerHaskellDevHarness.package}/bin/opencode debug agent hoogle-search > agent.json
      jq -e '.name == "hoogle-search"' agent.json >/dev/null
      jq -e '.mode == "subagent"' agent.json >/dev/null

      echo ok > $out
    '';
```

- [ ] **Step 2: Run the new check**

Run: `nix flake check .#wire-server-haskell-dev`
Expected: PASS (config, mcp wiring, rule, agent, skill all asserted).

- [ ] **Step 3: Commit**

```bash
git add flake.nix
git commit -m "feat: flake check for wire-server-haskell-dev harness"
```

---

### Task 7: Format, full check, manual smoke test

**Files:**
- Modify: formatting of `flake.nix` and all new `.nix` files (via `nix fmt`); commit any formatting drift.

- [ ] **Step 1: Format**

Run: `nix fmt`
Expected: no diffs after formatting if files were already nixfmt-clean; any diffs get applied.

- [ ] **Step 2: Full flake check**

Run: `git add -A && nix flake check`
Expected: all checks pass, including `checks.formatting`, `checks.wire-server-haskell-dev`, and the harness builds that run the hspec suite.

- [ ] **Step 3: Manual smoke test of the MCP server via the harness**

Run the harness devShell and query the `hoogle` tool through opencode:

```bash
nix develop .#wire-server-haskell-dev
# inside: invoke the `hoogle` MCP tool with a query, e.g. `map :: (a -> b) -> [a] -> [b]`
```

Also smoke-test the CLI both ways:

```bash
nix run .#wire-hoogle-mcp -- query "Data.Map.lookup" --count 5
nix run .#wire-hoogle-mcp -- query "Spar.API" --general --count 5
```

Expected: first returns Wire-instance results (links start with `https://hoogle.zinfra.io/file/nix/store/...`), second returns hackage links.

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "chore: format, final check"   # only if formatting produced diffs; otherwise skip
```

---

## Self-Review Notes

- **Spec coverage:** cabal project + MCP server (Task 1-4), mangling (Task 2), truncation/`full_docs`/`docs_truncated` (Task 2/3), LRU cache via `lrucache` + `HOOGLE_CACHE_MAX_ENTRIES` (Task 3), tool schema + descriptions (Task 4), rule (Task 5), sub-agent (Task 5), harness + llmaas variant + flake wiring + no-jail + `callCabal2nix` (Task 5), flake check (Task 6), `--help` via `helper` (Task 4), verification gate (Task 7).
- **No placeholders:** all code blocks are complete.
- **Type consistency:** `Config`, `QueryParams`, `Server`, `HoogleEntry`, `HoogleCache`, `cacheKey`, `cachedQuery`, `runQuery`, `runServer`, `parseCommand`/`runCommand` are defined once and reused consistently across tasks.