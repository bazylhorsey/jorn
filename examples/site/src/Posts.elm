module Posts exposing (Post, all, find)

{-| The posts. They're Elm values, so the site builds a page for each one,
and the app shows the same ones in the browser.
-}


type alias Post =
    { slug : String
    , title : String
    , date : String
    , summary : String
    , body : List String
    }


all : List Post
all =
    [ { slug = "pages-from-a-list"
      , title = "Pages from a list"
      , date = "2026-10-20"
      , summary = "Every post is a value in Posts.elm, and the site has a page for each."
      , body =
            [ "Each post here is a record in src/Posts.elm. The app's routes come from the same list, so a post's address is something the app knows about, and Route.all lists every page there is."
            , "src/Site.elm turns that list into pages. Adding a post adds its page, its link on the front page, and its line in the sitemap, and nothing else has to change."
            ]
      }
    , { slug = "the-same-view-twice"
      , title = "The same view, twice"
      , date = "2026-10-21"
      , summary = "A page's HTML comes from the app's own view, so the app can take over without anything moving."
      , body =
            [ "When the site is built, each page gets the HTML of the app's view at that page's address. That's what you see first, and what search engines read."
            , "Then the app starts at the same address, with the same flags, and mounts the same view over that HTML. Nothing on the screen changes, but from then on the page is the app."
            ]
      }
    , { slug = "links-that-stay"
      , title = "Links that stay on the page"
      , date = "2026-10-22"
      , summary = "Once the app is running, a link changes the address and the view instead of loading a page."
      , body =
            [ "Every link here is an ordinary link to a page that exists. Before the app has started, or without JavaScript, following one loads that page's HTML."
            , "Once the app is running, it gets the click instead. It pushes the new address and shows the post, so the page doesn't load again, and the back button still works."
            ]
      }
    ]


find : String -> Maybe Post
find slug =
    List.head (List.filter (\post -> post.slug == slug) all)
