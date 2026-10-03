{-# LANGUAGE OverloadedStrings #-}

module TypesSpec (spec) where

import qualified Data.Aeson as Aeson
import Data.Aeson (eitherDecodeStrict')
import qualified Data.ByteString as BS
import qualified Data.Text as T
import qualified Data.Text.Encoding as T
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)
import Wire.Hoogle.Types (CachedEntry(..), HoogleResult(..), HoogleUrl(..), OutputEntry(..), toOutputEntry, truncateDocs)

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
      let Right (r0 : r1 : _) = results
      hrItem r0 `shouldBe` "map :: (a -> b) -> [a] -> [b]"
      huName (hrPackage r0) `shouldBe` Just "base"
      huName (hrModule r0) `shouldBe` Just "Prelude"
      hrItem r1 `shouldBe` "package wire-api"
      huName (hrPackage r1) `shouldBe` Nothing
  describe "ToJSON OutputEntry" $ do
    it "emits the documented keys incl. docs_truncated and source_link" $ do
      let entry = OutputEntry (Just "base") (Just "Prelude") "map :: (a -> b) -> [a] -> [b]" "docs" True (Just "https://x") (Just "https://src")
          text = T.decodeUtf8 (BS.toStrict (Aeson.encode entry))
      text `shouldSatisfy` T.isInfixOf "\"docs_truncated\":true"
      text `shouldSatisfy` T.isInfixOf "\"link\":\"https://x\""
      text `shouldSatisfy` T.isInfixOf "\"source_link\":\"https://src\""
    it "emits null for a missing source link" $ do
      let entry = OutputEntry Nothing Nothing "id" "docs" False Nothing Nothing
          text = T.decodeUtf8 (BS.toStrict (Aeson.encode entry))
      text `shouldSatisfy` T.isInfixOf "\"source_link\":null"
  describe "truncateDocs" $ do
    it "leaves short docs untruncated" $
      truncateDocs 10 "short" `shouldBe` ("short", False)
    it "truncates long docs and flags it" $
      truncateDocs 10 (T.replicate 20 "x") `shouldBe` (T.replicate 10 "x", True)
  describe "toOutputEntry" $ do
    it "leaves short docs untruncated and passes the cached source link through" $
      toOutputEntry False (CachedEntry (Just "base") (Just "Control.Monad") "forever" "short" (Just "https://hoogle.zinfra.io/file/nix/store/x-doc/html/Control-Monad.html#v:forever") (Just "https://hoogle.zinfra.io/file/nix/store/x-doc/html/src/GHC.Internal.Control.Monad.html#forever"))
        `shouldBe` OutputEntry
          (Just "base")
          (Just "Control.Monad")
          "forever"
          "short"
          False
          (Just "https://hoogle.zinfra.io/file/nix/store/x-doc/html/Control-Monad.html#v:forever")
          (Just "https://hoogle.zinfra.io/file/nix/store/x-doc/html/src/GHC.Internal.Control.Monad.html#forever")
    it "truncates long docs and flags it" $
      toOutputEntry False (CachedEntry (Just "base") (Just "Prelude") "map" (T.replicate 1000 "x") Nothing Nothing)
        `shouldBe` OutputEntry (Just "base") (Just "Prelude") "map" (T.replicate 500 "x") True Nothing Nothing
    it "keeps full docs when fullDocs" $
      toOutputEntry True (CachedEntry (Just "base") (Just "Prelude") "map" (T.replicate 1000 "x") (Just "https://x") (Just "https://src"))
        `shouldBe` OutputEntry (Just "base") (Just "Prelude") "map" (T.replicate 1000 "x") False (Just "https://x") (Just "https://src")