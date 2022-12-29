USING: kernel locals threads ui.gadgets.charts ui.gadgets.charts.lines ui.gadgets.charts.axes ;
IN: ui.gadgets.charts.live

TUPLE: live-chart < chart updater { paused initial: f } ;

M: live-chart ungraft* t >>paused drop ;

: calculated-axis-limits ( x y -- x-y-limits )
    [ [ infimum ] [ supremum ] bi 2array ] bi@ 2array ; 

: valid-axis-limits? ( x-y-limits -- ? )
    [ first2 swap - 0.0 = not ] map first2 and ;

:: update-axes ( gadget data -- )
    data [ 0 <column> ] [ 1 <column> ] bi
    2dup
    [ length 1 > ] bi@ and
    [
        calculated-axis-limits
        { [ valid-axis-limits? ]
        [ gadget axes>> = not ] ! check if different to existing
        [ gadget swap >>axes relayout-1 t ] } 1&& drop
    ] [ 2drop ] if ;

:: start-chart-thread ( gadget -- )
    [
        [ gadget paused>> ]
        [
            gadget updater>> call( -- x/? )
            [
                gadget children>>
                [
                    dup line?
                    [
                        [ data>> [ [ fourth ] [ second ] bi 2array ] dip push ]
                        [ gadget swap data>> update-axes ]
                        [ relayout-1 ] tri ! TODO limit amount of redrawing
                    ] [ drop ] if
                ] each
                yield
            ] when*
        ] until
    ] in-thread
    ;

: (live-chart) ( quot -- gadget )
    live-chart new ${ ${ -10 10 } { -10 10 } } >>axes swap >>updater
    line new link-color >>color V{ } clone >>data add-gadget
    vertical-axis new add-gadget
    horizontal-axis new add-gadget
    white-interior ;

: valid-csv-input? ( seq -- ? ) { "" } = not ;

: inactive-delay ( -- ) 15 milliseconds sleep ;

: csv-live-demo ( -- gadget )
    [ read-row dup valid-csv-input?
        [ [ string>number ] map ] [ drop inactive-delay f ] if
    ] (live-chart) 
    [ start-chart-thread ] keep ;

MAIN-WINDOW: live-chart-window { { title "live-chart" } }
    csv-live-demo >>gadgets ;

