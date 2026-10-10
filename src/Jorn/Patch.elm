module Jorn.Patch exposing (Patch, diff, encode, encodeHtml)

{-| Diff two trees into a list of patches, and encode them for the wire.


    patches =
        Jorn.Patch.diff previousView nextView

    -- send `Jorn.Patch.encode patches` to the client through a port

The wire format is specified in
[PROTOCOL.md](https://github.com/bazylhorsey/jorn/blob/main/PROTOCOL.md).

@docs Patch, diff, encode, encodeHtml

-}

import Jorn.Html exposing (Html)
import Jorn.Internal.Patch as Internal
import Jorn.Internal.Vdom as Vdom
import Json.Encode exposing (Value)


{-| One change to apply to the client's DOM.
-}
type alias Patch =
    Internal.Patch


{-| The patches that turn the first tree into the second. Applying them in
order is always valid. Identical trees produce `[]`.
-}
diff : Html msg -> Html msg -> List Patch
diff =
    Internal.diff


{-| Encode patches as a JSON array.
-}
encode : List Patch -> Value
encode =
    Internal.encode


{-| Encode a whole tree, for the initial mount.
-}
encodeHtml : Html msg -> Value
encodeHtml html =
    Vdom.encodeNode (Vdom.toNode html)
