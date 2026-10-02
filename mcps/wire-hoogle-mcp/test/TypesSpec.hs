{-# LANGUAGE OverloadedStrings #-}

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