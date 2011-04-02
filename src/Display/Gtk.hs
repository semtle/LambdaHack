module Display.Gtk
  (displayId, startup, shutdown,
   display, nextEvent, setBG, setFG, defaultAttr, Session) where

import qualified Data.Binary
import Control.Monad
import Control.Concurrent
import Graphics.UI.Gtk.Gdk.Events  -- TODO: replace, deprecated
import Graphics.UI.Gtk hiding (Attr)
import Data.List as L
import Data.IORef
import Data.Map as M

import Geometry
import qualified Keys as K (K.Key(..), K.keyTranslate)
import qualified Color

displayId = "gtk"

data Session =
  Session {
    schan :: Chan String,
    stags :: Map Attr TextTag,
    sview :: TextView }

startup :: (Session -> IO ()) -> IO ()
startup k =
  do
    -- initGUI
    unsafeInitGUIForThreadedRTS
    w <- windowNew

    ttt <- textTagTableNew
    -- text attributes
    tts <- fmap M.fromList $
           mapM (\ ak -> do
                           tt <- textTagNew Nothing
                           textTagTableAdd ttt tt
                           doAttr tt ak
                           return (ak, tt))
                [ (f, b) |
                  f <- Nothing : L.map Just [minBound..maxBound],
                  b <- Nothing : L.map Just Color.legalBG ]

    -- text buffer
    tb <- textBufferNew (Just ttt)
    textBufferSetText tb (unlines (replicate 25 (replicate 80 ' ')))

    -- create text view
    tv <- textViewNewWithBuffer tb
    containerAdd w tv
    textViewSetEditable tv False
    textViewSetCursorVisible tv False

    -- font
    f <- fontDescriptionNew
    fontDescriptionSetFamily f "Monospace"
    fontDescriptionSetSize f 12
    widgetModifyFont tv (Just f)
    currentfont <- newIORef f
    onButtonPress tv (\ e -> case e of
                               Button { Graphics.UI.Gtk.Gdk.Events.eventButton = RightButton } ->
                                 do
                                   fsd <- fontSelectionDialogNew "Choose font"
                                   cf <- readIORef currentfont
                                   fd <- fontDescriptionToString cf
                                   fontSelectionDialogSetFontName fsd fd
                                   fontSelectionDialogSetPreviewText fsd "+##@##-...|"
                                   response <- dialogRun fsd
                                   when (response == ResponseOk) $
                                     do
                                       fn <- fontSelectionDialogGetFontName fsd
                                       case fn of
                                         Just fn' -> do
                                                       fd <- fontDescriptionFromString fn'
                                                       writeIORef currentfont fd
                                                       widgetModifyFont tv (Just fd)
                                         Nothing  -> return ()
                                   widgetDestroy fsd
                                   return True
                               _ -> return False)

    let black = Color minBound minBound minBound  -- Color.defBG == Color.Black
        white = Color 0xAAAA 0xAAAA 0xAAAA        -- Color.defFG == Color.White
    widgetModifyBase tv StateNormal black
    widgetModifyText tv StateNormal white

    ec <- newChan
    forkIO $ k (Session ec tts tv)

    onKeyPress tv (\ e -> postGUIAsync (writeChan ec (Graphics.UI.Gtk.Gdk.Events.eventKeyName e)) >> return True)

    onDestroy w mainQuit -- set quit handler
    widgetShowAll w
    yield
    mainGUI

shutdown _ = mainQuit

display :: Area -> Session -> (Loc -> (Attr, Char)) -> String -> String -> IO ()
display ((y0,x0), (y1,x1)) session f msg status =
  postGUIAsync $
  do
    tb <- textViewGetBuffer (sview session)
    let text = unlines [ [ snd (f (y, x)) | x <- [x0..x1] ] | y <- [y0..y1] ]
    textBufferSetText tb (msg ++ "\n" ++ text ++ status)
    sequence_ [ setTo tb (stags session) (y, x) (fst (f (y, x))) |
                y <- [y0..y1], x <- [x0..x1]]

setTo :: TextBuffer -> Map Attr TextTag -> Loc -> Attr -> IO ()
setTo _ _ _ (Nothing, Nothing) = return ()
setTo tb tts (ly, lx) a =
  do
    ib <- textBufferGetIterAtLineOffset tb (ly + 1) lx
    ie <- textIterCopy ib
    textIterForwardChar ie
    textBufferApplyTag tb (tts ! a) ib ie

-- | reads until a non-dead key encountered
readUndeadChan :: Chan String -> IO String
readUndeadChan ch =
  do
    x <- readChan ch
    if dead x then readUndeadChan ch else return x
      where
        dead x =
          case x of
            "Shift_R"          -> True
            "Shift_L"          -> True
            "Control_L"        -> True
            "Control_R"        -> True
            "Super_L"          -> True
            "Super_R"          -> True
            "Menu"             -> True
            "Alt_L"            -> True
            "Alt_R"            -> True
            "ISO_Level2_Shift" -> True
            "ISO_Level3_Shift" -> True
            "ISO_Level2_Latch" -> True
            "ISO_Level3_Latch" -> True
            "Num_Lock"         -> True
            "Caps_Lock"        -> True
            _                  -> False

nextEvent :: Session -> IO K.Key
nextEvent session =
  do
    e <- readUndeadChan (schan session)
    return (K.keyTranslate e)

type Attr = (Maybe Color.Color, Maybe Color.Color)

setFG c (_, b) = (Just c, b)
setBG c (f, _) = (f, Just c)
defaultAttr = (Nothing, Nothing)

doAttr :: TextTag -> Attr -> IO ()
doAttr tt (Nothing, Nothing) = return ()
doAttr tt (Just fg, Nothing) = set tt [textTagForeground := Color.colorToRGB fg]
doAttr tt (Nothing, Just bg) = set tt [textTagBackground := Color.colorToRGB bg]
doAttr tt (Just fg, Just bg) = set tt [textTagForeground := Color.colorToRGB fg,
                                       textTagBackground := Color.colorToRGB bg]
