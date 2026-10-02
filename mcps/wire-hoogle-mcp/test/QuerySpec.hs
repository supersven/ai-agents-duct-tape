{-# LANGUAGE OverloadedStrings #-}

module QuerySpec (spec) where

import qualified Data.Text as T
import Test.Hspec (Spec, describe, it, shouldBe)
import Wire.Hoogle.Query (buildSearchUrl, toEntry)
import Wire.Hoogle.Types (HoogleEntry(..), HoogleResult(..), HoogleUrl(..))

spec :: Spec
spec = do
  describe "buildSearchUrl" $ do
    it "url-encodes the query and appends count" $
      buildSearchUrl "https://hoogle.zinfra.io" "a -> b" 10
        `shouldBe` "https://hoogle.zinfra.io?mode=json&format=text&hoogle=a%20-%3E%20b&count=10"
  describe "toEntry" $ do
    it "keeps full docs and mangles file:// links when fullDocs" $ do
      let result = HoogleResult
            { hrItem = "map :: (a -> b) -> [a] -> [b]"
            , hrDocs = "long docs that stay"
            , hrUrl = Just "file:///nix/store/abc-wire-api-0.1.0-doc/foo.html"
            , hrPackage = HoogleUrl (Just "base") Nothing
            , hrModule = HoogleUrl (Just "Prelude") Nothing
            }
          entry = toEntry "https://hoogle.zinfra.io" True result
      heItem entry `shouldBe` "map :: (a -> b) -> [a] -> [b]"
      heDocs entry `shouldBe` "long docs that stay"
      heDocsTruncated entry `shouldBe` False
      heLink entry `shouldBe` Just "https://hoogle.zinfra.io/file/nix/store/abc-wire-api-0.1.0-doc/foo.html"
    it "truncates long docs and flags it unless fullDocs" $ do
      let longDocs = T.replicate 1000 "x"
          entry = toEntry "https://hoogle.zinfra.io" False HoogleResult
            { hrItem = "id"
            , hrDocs = longDocs
            , hrUrl = Nothing
            , hrPackage = HoogleUrl Nothing Nothing
            , hrModule = HoogleUrl Nothing Nothing
            }
      heDocs entry `shouldBe` T.take 500 longDocs
      heDocsTruncated entry `shouldBe` True