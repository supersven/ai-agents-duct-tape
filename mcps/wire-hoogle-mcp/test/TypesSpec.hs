{-# LANGUAGE OverloadedStrings #-}

module TypesSpec (spec) where

import qualified Data.Aeson as Aeson
import Data.Aeson (eitherDecodeStrict')
import qualified Data.ByteString as BS
import Data.Maybe (fromJust)
import qualified Data.Text as T
import qualified Data.Text.Encoding as T
import Network.URI (URI, parseURI)
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)
import Wire.Hoogle.Types (CachedEntry(..), HoogleResult(..), HoogleUrl(..), OutputEntry(..), dedupeBySourceLink, toOutputEntry, truncateDocs)

uri :: String -> URI
uri = fromJust . parseURI

sampleJson :: BS.ByteString
sampleJson = T.encodeUtf8 $ T.unlines
  [ "["
  , "  {\"url\":\"https://hackage.haskell.org/package/base/docs/Prelude.html#v:map\","
  , "   \"module\":{\"url\":\"https://hackage.haskell.org/package/base/docs/Prelude.html\",\"name\":\"Prelude\"},"
  , "   \"package\":{\"url\":\"https://hackage.haskell.org/package/base\",\"name\":\"base\"},"
  , "   \"item\":\"map :: (a -> b) -> [a] -> [b]\",\"type\":\"\",\"docs\":\"map f xs is ...\"},"
  , "  {\"url\":\"file:///nix/store/h-wire-api-0.1.0-doc/share/doc/wire-api-0.1.0/html/Wire-API.html\","
  , "   \"module\":{},\"package\":{},\"item\":\"package wire-api\",\"type\":\"package\",\"docs\":\"API types\"},"
  , "  {\"url\":\"not a uri\","
  , "   \"module\":{},\"package\":{},\"item\":\"package x\",\"type\":\"package\",\"docs\":\"bad url\"}"
  , "]"
  ]

spec :: Spec
spec = do
  describe "FromJSON HoogleResult" $ do
    it "parses both result shapes" $ do
      let results = eitherDecodeStrict' sampleJson :: Either String [HoogleResult]
      results `shouldSatisfy` either (const False) (const True)
      let Right (r0 : r1 : _) = results
      hrItem r0 `shouldBe` "map :: (a -> b) -> [a] -> [b]"
      huName (hrPackage r0) `shouldBe` Just "base"
      huName (hrModule r0) `shouldBe` Just "Prelude"
      hrType r0 `shouldBe` ""
      hrUrl r0 `shouldBe` Just (uri "https://hackage.haskell.org/package/base/docs/Prelude.html#v:map")
      hrItem r1 `shouldBe` "package wire-api"
      huName (hrPackage r1) `shouldBe` Nothing
      hrType r1 `shouldBe` "package"
    it "yields Nothing for an unparseable url" $ do
      let Right (_ : _ : r2 : _) = eitherDecodeStrict' sampleJson :: Either String [HoogleResult]
      hrUrl r2 `shouldBe` Nothing
  describe "ToJSON OutputEntry" $ do
    it "emits the documented keys incl. docs_truncated and source_link" $ do
      let entry = OutputEntry (Just "base") (Just "Prelude") "map :: (a -> b) -> [a] -> [b]" "docs" True (Just "https://x") (Just "https://src") (Just "module") ["yaml/Data.Yaml"]
          text = T.decodeUtf8 (BS.toStrict (Aeson.encode entry))
      text `shouldSatisfy` T.isInfixOf "\"docs_truncated\":true"
      text `shouldSatisfy` T.isInfixOf "\"link\":\"https://x\""
      text `shouldSatisfy` T.isInfixOf "\"source_link\":\"https://src\""
      text `shouldSatisfy` T.isInfixOf "\"type\":\"module\""
      text `shouldSatisfy` T.isInfixOf "\"also_in\":[\"yaml/Data.Yaml\"]"
    it "emits null for a missing source link and empty also_in" $ do
      let entry = OutputEntry Nothing Nothing "id" "docs" False Nothing Nothing Nothing []
          text = T.decodeUtf8 (BS.toStrict (Aeson.encode entry))
      text `shouldSatisfy` T.isInfixOf "\"source_link\":null"
      text `shouldSatisfy` T.isInfixOf "\"type\":null"
      text `shouldSatisfy` T.isInfixOf "\"also_in\":[]"
  describe "truncateDocs" $ do
    it "leaves short docs untruncated" $
      truncateDocs 10 "short" `shouldBe` ("short", False)
    it "truncates long docs and flags it" $
      truncateDocs 10 (T.replicate 20 "x") `shouldBe` (T.replicate 10 "x", True)
  describe "toOutputEntry" $ do
    it "leaves short docs untruncated and passes the cached source link through" $
      toOutputEntry False (CachedEntry (Just "base") (Just "Control.Monad") "forever" "short" (Just (uri "https://hoogle.zinfra.io/file/nix/store/x-doc/html/Control-Monad.html#v:forever")) (Just (uri "https://hoogle.zinfra.io/file/nix/store/x-doc/html/src/GHC.Internal.Control.Monad.html#forever")) "module" ["base/Control.Monad", "yaml/Data.Yaml"])
        `shouldBe` OutputEntry
          (Just "base")
          (Just "Control.Monad")
          "forever"
          "short"
          False
          (Just "https://hoogle.zinfra.io/file/nix/store/x-doc/html/Control-Monad.html#v:forever")
          (Just "https://hoogle.zinfra.io/file/nix/store/x-doc/html/src/GHC.Internal.Control.Monad.html#forever")
          (Just "module")
          ["base/Control.Monad", "yaml/Data.Yaml"]
    it "maps an empty type to Nothing" $
      toOutputEntry False (CachedEntry (Just "base") (Just "Prelude") "map" "short" Nothing Nothing "" [])
        `shouldBe` OutputEntry (Just "base") (Just "Prelude") "map" "short" False Nothing Nothing Nothing []
    it "truncates long docs and flags it" $
      toOutputEntry False (CachedEntry (Just "base") (Just "Prelude") "map" (T.replicate 1000 "x") Nothing Nothing "" [])
        `shouldBe` OutputEntry (Just "base") (Just "Prelude") "map" (T.replicate 500 "x") True Nothing Nothing Nothing []
    it "keeps full docs when fullDocs" $
      toOutputEntry True (CachedEntry (Just "base") (Just "Prelude") "map" (T.replicate 1000 "x") (Just (uri "https://x")) (Just (uri "https://src")) "package" [])
        `shouldBe` OutputEntry (Just "base") (Just "Prelude") "map" (T.replicate 1000 "x") False (Just "https://x") (Just "https://src") (Just "package") []
  describe "dedupeBySourceLink" $ do
    let e pkg mod item = CachedEntry (Just pkg) (Just mod) item "docs" (Just (uri "https://x")) (Just (uri ("https://src/" ++ T.unpack mod))) "" []
        e' mod src = CachedEntry (Just "base") (Just mod) "map" "docs" (Just (uri "https://x")) (Just (uri src)) "" []
    it "keeps the first entry per source link and merges the rest into also_in" $
      dedupeBySourceLink
        [ e' "Prelude" "https://src/GHC.Internal.Base.html#map"
        , e' "Data.List" "https://src/GHC.Internal.Base.html#map"
        , e' "GHC.Base" "https://src/GHC.Internal.Base.html#map"
        ]
        `shouldBe` [ (e' "Prelude" "https://src/GHC.Internal.Base.html#map")
                       { ceAlsoIn = ["base/Data.List", "base/GHC.Base"] }
                   ]
    it "keeps entries with distinct source links" $
      dedupeBySourceLink
        [ e "base" "Prelude" "map"
        , e "base" "Control.Monad" "forever"
        ]
        `shouldBe` [ e "base" "Prelude" "map"
                   , e "base" "Control.Monad" "forever"
                   ]
    it "keeps every entry without a source link, with empty also_in" $ do
      let noSrc = CachedEntry (Just "base") (Just "Prelude") "map" "docs" Nothing Nothing "" []
          a = noSrc
          b = noSrc
      dedupeBySourceLink [a, b] `shouldBe` [a, b]
    it "keeps entries with distinct real definitions (different source links)" $
      dedupeBySourceLink
        [ e "aeson" "Data.Aeson" "parseEither"
        , e "yaml" "Data.Yaml" "parseEither"
        ]
        `shouldBe` [ e "aeson" "Data.Aeson" "parseEither"
                   , e "yaml" "Data.Yaml" "parseEither"
                   ]
    it "deduplicates also_in across repeated identical collapsed rows" $
      dedupeBySourceLink
        [ e' "Prelude" "https://src/GHC.Internal.Base.html#map"
        , e' "Data.List" "https://src/GHC.Internal.Base.html#map"
        , e' "Data.List" "https://src/GHC.Internal.Base.html#map"
        ]
        `shouldBe` [ (e' "Prelude" "https://src/GHC.Internal.Base.html#map")
                       { ceAlsoIn = ["base/Data.List"] }
                   ]