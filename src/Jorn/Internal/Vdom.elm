module Jorn.Internal.Vdom exposing
    ( Attribute(..)
    , Closing(..)
    , Element(..)
    , EventOptions
    , Facts
    , Node(..)
    , defaultOptions
    , encodeNode
    , encodeOptions
    , facts
    , flatten
    , map
    , mapAttribute
    , root
    , toNode
    )

{-| Internal representation. Not exposed from the package, so constructors
stay private while tests and sibling modules can still see them.

`Element` carries decoders (it is what your program builds and what event routing
walks). `Node` is the msg-free projection of it: pure data, safe to serialize,
and what every patch and mount payload is made of.

-}

import Dict exposing (Dict)
import Json.Decode exposing (Decoder)
import Json.Encode as Encode exposing (Value)


type Element msg
    = Element String String Closing (List (Attribute msg)) (List (Element msg))
      -- namespace, tag, how it closes, attributes, children
    | Text String
    | Fragment (List (Element msg))


{-| How an element's tags are written as HTML. Only rendering to a string
cares: the DOM, the diff and the wire are the same for all three.
-}
type Closing
    = Normal
    | Void
    | SelfClosing


type Attribute msg
    = Attr String String
    | Prop String Value
    | On String (Decoder msg)
    | Options EventOptions (Attribute msg)


{-| Event options are static on purpose. A server component has to tell the
client up front whether to call preventDefault, because the decision can't
wait for a round trip. `include` lists the dotted event fields the client
must serialize and send back (for example `target.value`).

Options wrap the handler they apply to, and options on the same handler merge:
`preventDefault` and `stopPropagation` are true if any of them asked, and
`include` is the union of what they asked for. An option wrapped around
anything that isn't a handler is dropped, leaving the attribute as it was.

-}
type alias EventOptions =
    { preventDefault : Bool
    , stopPropagation : Bool
    , include : List String
    }


defaultOptions : EventOptions
defaultOptions =
    { preventDefault = False, stopPropagation = False, include = [] }



-- NORMALIZATION


{-| An element's attribute list folded into lookup tables. Later entries win,
except `class`, which accumulates like it does in elm/html.
-}
type alias Facts msg =
    { attrs : Dict String String
    , props : Dict String Value
    , events : Dict String ( EventOptions, Decoder msg )
    }


facts : List (Attribute msg) -> Facts msg
facts attributes =
    List.foldl addFact { attrs = Dict.empty, props = Dict.empty, events = Dict.empty } attributes


addFact : Attribute msg -> Facts msg -> Facts msg
addFact attribute acc =
    let
        ( options, bare ) =
            splitOptions attribute
    in
    case bare of
        Attr "class" value ->
            { acc | attrs = Dict.update "class" (mergeClass value) acc.attrs }

        Attr name value ->
            { acc | attrs = Dict.insert name value acc.attrs }

        Prop name value ->
            { acc | props = Dict.insert name value acc.props }

        On name decoder ->
            { acc | events = Dict.insert name ( options, decoder ) acc.events }

        Options _ _ ->
            acc


{-| Split an attribute into the options wrapped around it and the attribute
underneath, merging any nesting. Options around anything that isn't a handler
are simply dropped, leaving the attribute itself untouched.
-}
splitOptions : Attribute msg -> ( EventOptions, Attribute msg )
splitOptions attribute =
    case attribute of
        Options added wrapped ->
            let
                ( nested, bare ) =
                    splitOptions wrapped
            in
            ( combineOptions added nested, bare )

        _ ->
            ( defaultOptions, attribute )


combineOptions : EventOptions -> EventOptions -> EventOptions
combineOptions added options =
    { preventDefault = added.preventDefault || options.preventDefault
    , stopPropagation = added.stopPropagation || options.stopPropagation
    , include = addPaths added.include options.include
    }


addPaths : List String -> List String -> List String
addPaths paths existing =
    List.foldl
        (\path acc ->
            if List.member path acc then
                acc

            else
                acc ++ [ path ]
        )
        existing
        paths


mergeClass : String -> Maybe String -> Maybe String
mergeClass value existing =
    case existing of
        Nothing ->
            Just value

        Just previous ->
            if String.isEmpty value then
                Just previous

            else if String.isEmpty previous then
                Just value

            else
                Just (previous ++ " " ++ value)



-- FRAGMENTS


{-| Splice fragments into the surrounding list of children, at any depth.
Fragments never reach the wire: paths, patches and mounts only ever see the
flattened children. Most lists hold no fragments, and those come back as they
are, without being rebuilt.
-}
flatten : List (Element msg) -> List (Element msg)
flatten children =
    if List.any isFragment children then
        List.foldr spliceChild [] children

    else
        children


spliceChild : Element msg -> List (Element msg) -> List (Element msg)
spliceChild child acc =
    case child of
        Fragment grandchildren ->
            List.foldr spliceChild acc grandchildren

        _ ->
            child :: acc


isFragment : Element msg -> Bool
isFragment html =
    case html of
        Fragment _ ->
            True

        _ ->
            False


{-| The node a view puts on screen. A view's root is a single node on the
wire, so a fragment at the root needs a stand-in: with no children it's an
empty text node, with one it's that child, and with several they're wrapped in
a `jorn-fragment` element styled `display: contents`, which leaves layout as
if the wrapper weren't there.
-}
root : Element msg -> Element msg
root html =
    case html of
        Fragment children ->
            case flatten children of
                [] ->
                    Text ""

                [ only ] ->
                    only

                several ->
                    Element "" "jorn-fragment" Normal [ Attr "style" "display: contents" ] several

        _ ->
            html



-- PROJECTION


type Node
    = NodeElement
        { namespace : String
        , tag : String
        , attrs : Dict String String
        , props : Dict String Value
        , events : Dict String EventOptions
        , children : List Node
        }
    | NodeText String


toNode : Element msg -> Node
toNode html =
    case html of
        Text content ->
            NodeText content

        Fragment _ ->
            toNode (root html)

        Element namespace tag _ attributes children ->
            let
                f =
                    facts attributes
            in
            NodeElement
                { namespace = namespace
                , tag = tag
                , attrs = f.attrs
                , props = f.props
                , events = Dict.map (\_ ( options, _ ) -> options) f.events
                , children = List.map toNode (flatten children)
                }


encodeNode : Node -> Value
encodeNode node =
    case node of
        NodeText content ->
            Encode.object [ ( "text", Encode.string content ) ]

        NodeElement r ->
            Encode.object
                [ ( "tag", Encode.string r.tag )
                , ( "namespace", Encode.string r.namespace )
                , ( "attrs", Encode.dict identity Encode.string r.attrs )
                , ( "props", Encode.dict identity identity r.props )
                , ( "events", Encode.dict identity encodeOptions r.events )
                , ( "children", Encode.list encodeNode r.children )
                ]


encodeOptions : EventOptions -> Value
encodeOptions options =
    Encode.object
        [ ( "preventDefault", Encode.bool options.preventDefault )
        , ( "stopPropagation", Encode.bool options.stopPropagation )
        , ( "include", Encode.list Encode.string options.include )
        ]



-- MAPPING


{-| Eager: walks the subtree and wraps every decoder. elm/html makes `map`
lazy with kernel code, which a pure package can't do. Lazy map is on the roadmap.
-}
map : (a -> b) -> Element a -> Element b
map f html =
    case html of
        Text content ->
            Text content

        Element namespace tag closing attributes children ->
            Element namespace tag closing (List.map (mapAttribute f) attributes) (List.map (map f) children)

        Fragment children ->
            Fragment (List.map (map f) children)


mapAttribute : (a -> b) -> Attribute a -> Attribute b
mapAttribute f attribute =
    case attribute of
        Attr name value ->
            Attr name value

        Prop name value ->
            Prop name value

        On name decoder ->
            On name (Json.Decode.map f decoder)

        Options options wrapped ->
            Options options (mapAttribute f wrapped)
