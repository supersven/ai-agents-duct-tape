{-# LANGUAGE OverloadedStrings #-}

module SourceSpec (spec) where

import Data.IORef (modifyIORef', newIORef, readIORef)
import qualified Data.Map.Strict as Map
import qualified Data.Text as T
import Test.Hspec (Spec, describe, it, shouldBe)
import Wire.Hoogle.Source (extractSourceLinks, newSourceCache, pageHrefsWith, resolveHref, resolveSourceLinksWith)
import Wire.Hoogle.Types (CachedEntry(..))

spec :: Spec
spec = do
  describe "extractSourceLinks" $ do
    it "maps a re-exported def anchor to its Source href" $ do
      extractSourceLinks
        "<html><div class=\"top\"><p class=\"src\"><a id=\"v:forever\" class=\"def\">forever</a> :: Applicative f => f a -> f b \
        \<a href=\"../ghc-internal-9.1003.0-33ec/src/GHC.Internal.Control.Monad.html#forever\" class=\"link\">Source</a> \
        \<a href=\"#v:forever\" class=\"selflink\">#</a></p></div></html>"
        `shouldBe` Map.fromList
          [ ("v:forever", "../ghc-internal-9.1003.0-33ec/src/GHC.Internal.Control.Monad.html#forever") ]
    it "maps a type anchor to its Source href" $ do
      extractSourceLinks
        "<p class=\"src\"><span class=\"keyword\">data</span> <a id=\"t:Map\" class=\"def\">Map</a> k a \
        \<a href=\"src/Data.Map.Internal.html#Map\" class=\"link\">Source</a> \
        \<a href=\"#t:Map\" class=\"selflink\">#</a></p>"
        `shouldBe` Map.fromList
          [ ("t:Map", "src/Data.Map.Internal.html#Map") ]
    it "ignores synopsis hrefs (no id, no Source) and other class=link anchors" $ do
      extractSourceLinks
        "<p class=\"src\"><a href=\"#v:map\">map</a> :: (a -> b) -> [a] -> [b]</p>\
        \<p class=\"src\"><a id=\"v:map\" class=\"def\">map</a> :: (a -> b) -> [a] -> [b] \
        \<a href=\"src/Data.Map.html#map\" class=\"link\">Source</a></p>"
        `shouldBe` Map.fromList
          [ ("v:map", "src/Data.Map.html#map") ]
    it "does not attribute later instance Source links to constructors" $ do
      extractSourceLinks
        "<div class=\"top\"><p class=\"src\"><span class=\"keyword\">data</span> \
        \<a id=\"t:Bool\" class=\"def\">Bool</a> \
        \<a href=\"src/GHC.Types.html#Bool\" class=\"link\">Source</a> \
        \<a href=\"#t:Bool\" class=\"selflink\">#</a></p>\
        \<div class=\"subs constructors\"><p class=\"caption\">Constructors</p><table>\
        \<tr><td class=\"src\"><a id=\"v:False\" class=\"def\">False</a></td><td class=\"doc empty\">&nbsp;</td></tr>\
        \<tr><td class=\"src\"><a id=\"v:True\" class=\"def\">True</a></td><td class=\"doc empty\">&nbsp;</td></tr>\
        \</table></div>\
        \<div class=\"subs instances\"><h4 class=\"instances\">Instances</h4><table>\
        \<tr><td colspan=\"2\"><details id=\"i:Bool:1\"><summary>Instance details</summary>\
        \<p>Defined in <a href=\"GHC-Internal-Bits.html\">GHC.Internal.Bits</a></p>\
        \<div class=\"subs methods\"><p class=\"caption\">Methods</p>\
        \<p class=\"src\"><a href=\"#v:.-38-.\">(.&amp;.)</a> :: Bool -&gt; Bool -&gt; Bool \
        \<a href=\"src/GHC.Internal.Bits.html#.%26.\" class=\"link\">Source</a></p>\
        \</div></details></td></tr></table></div></div>"
        `shouldBe` Map.fromList
          [ ("t:Bool", "src/GHC.Types.html#Bool") ]
  describe "resolveHref" $ do
    it "resolves a same-directory relative Source href" $
      resolveHref "https://hoogle.zinfra.io/file/nix/store/x-doc/html/Data-Aeson-KeyMap.html" "src/Data.Aeson.KeyMap.html#map"
        `shouldBe` Just "https://hoogle.zinfra.io/file/nix/store/x-doc/html/src/Data.Aeson.KeyMap.html#map"
    it "resolves a ../ Source href to the sibling package" $
      resolveHref "https://hoogle.zinfra.io/file/nix/store/x-doc/html/libraries/base-4.20.2.0-4d66/Control-Monad.html" "../ghc-internal-9.1003.0-33ec/src/GHC.Internal.Control.Monad.html#forever"
        `shouldBe` Just "https://hoogle.zinfra.io/file/nix/store/x-doc/html/libraries/ghc-internal-9.1003.0-33ec/src/GHC.Internal.Control.Monad.html#forever"
    it "resolves an absolute-path hackage Source href" $
      resolveHref "https://hackage.haskell.org/package/base/docs/Control-Monad.html" "/package/ghc-internal-9.1401.0/docs/src/GHC.Internal.Control.Monad.html#forever"
        `shouldBe` Just "https://hackage.haskell.org/package/ghc-internal-9.1401.0/docs/src/GHC.Internal.Control.Monad.html#forever"
  describe "resolveSourceLinksWith" $ do
    it "fills ceSourceLink from the stubbed page and leaves unlinkable entries alone" $ do
      calls <- newIORef (0 :: Int)
      let pageFetch page = modifyIORef' calls (+ 1) >> pure (Map.singleton "v:forever" "../ghc-internal-9.1003.0-33ec/src/GHC.Internal.Control.Monad.html#forever")
          entries =
            [ CachedEntry (Just "base") (Just "Control.Monad") "forever" "d" (Just "https://hoogle.zinfra.io/file/nix/store/x-doc/html/libraries/base-4.20.2.0-4d66/Control-Monad.html#v:forever") Nothing
            , CachedEntry (Just "base") (Just "Prelude") "no-source" "d" (Just "https://hoogle.zinfra.io/file/nix/store/x-doc/html/libraries/base-4.20.2.0-4d66/Prelude.html#v:nosuch") Nothing
            , CachedEntry (Just "base") (Just "Prelude") "no-link" "d" Nothing Nothing
            ]
      resolved <- resolveSourceLinksWith pageFetch entries
      case resolved of
        [e0, e1, e2] -> do
          ceSourceLink e0 `shouldBe` Just "https://hoogle.zinfra.io/file/nix/store/x-doc/html/libraries/ghc-internal-9.1003.0-33ec/src/GHC.Internal.Control.Monad.html#forever"
          ceSourceLink e1 `shouldBe` Nothing
          ceSourceLink e2 `shouldBe` Nothing
        _ -> error "expected three entries"
      n <- readIORef calls
      n `shouldBe` 2
    it "reuses a cached page map across entries" $ do
      calls <- newIORef (0 :: Int)
      cache <- newSourceCache 10
      let pageFetch page = modifyIORef' calls (+ 1) >> pure (Map.singleton "v:x" ("src/Mod.html#x" :: T.Text))
          entries =
            [ CachedEntry Nothing Nothing "a" "d" (Just "https://h/p.html#v:x") Nothing
            , CachedEntry Nothing Nothing "b" "d" (Just "https://h/p.html#v:x") Nothing
            ]
      _ <- pageHrefsWith cache pageFetch "https://h/p.html"
      _ <- pageHrefsWith cache pageFetch "https://h/p.html"
      n <- readIORef calls
      n `shouldBe` 1
    it "resolves the same name on different pages independently" $ do
      let pageFetch page
            | page == "https://h/Data-List.html" = pure (Map.singleton "v:map" "src/Data.List.html#map")
            | page == "https://h/Data-Map.html" = pure (Map.singleton "v:map" "src/Data.Map.Strict.html#map")
            | otherwise = pure Map.empty
          entries =
            [ CachedEntry (Just "base") (Just "Data.List") "map" "d" (Just "https://h/Data-List.html#v:map") Nothing
            , CachedEntry (Just "containers") (Just "Data.Map") "map" "d" (Just "https://h/Data-Map.html#v:map") Nothing
            ]
      resolved <- resolveSourceLinksWith pageFetch entries
      case resolved of
        [e0, e1] -> do
          ceSourceLink e0 `shouldBe` Just "https://h/src/Data.List.html#map"
          ceSourceLink e1 `shouldBe` Just "https://h/src/Data.Map.Strict.html#map"
        _ -> error "expected two entries"
    it "does not cache an empty page map (transient fetch failure)" $ do
      calls <- newIORef (0 :: Int)
      cache <- newSourceCache 10
      let pageFetch page = modifyIORef' calls (+ 1) >> pure Map.empty
      _ <- pageHrefsWith cache pageFetch "https://h/p.html"
      _ <- pageHrefsWith cache pageFetch "https://h/p.html"
      n <- readIORef calls
      n `shouldBe` 2