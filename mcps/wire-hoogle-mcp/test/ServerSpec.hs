{-# LANGUAGE OverloadedStrings #-}

module ServerSpec (spec) where

import qualified Data.Text as T
import MCP.Server (ToolDefinition(..))
import Test.Hspec (Spec, describe, it, runIO, shouldNotSatisfy, shouldSatisfy)
import Wire.Hoogle.Server (toolList)

spec :: Spec
spec = describe "toolList" $ do
  desc <- runIO $ do
    tools <- toolList
    pure (T.pack (show (map toolDefinitionDescription tools)))
  it "documents the real hoogle scope-filter syntax (bare +packagename)" $ do
    desc `shouldSatisfy` T.isInfixOf "+packagename"
    desc `shouldSatisfy` T.isInfixOf "-packagename"
    desc `shouldSatisfy` T.isInfixOf "+Module.Name"
  it "does not document the broken +pkg/-pkg/+Package forms" $ do
    desc `shouldNotSatisfy` T.isInfixOf "+pkg"
    desc `shouldNotSatisfy` T.isInfixOf "-pkg"
    desc `shouldNotSatisfy` T.isInfixOf "+Package"