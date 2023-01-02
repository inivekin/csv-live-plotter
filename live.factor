USING: kernel locals math.matrices math.transforms.fft threads
ui.gadgets.charts ui.gadgets.charts.lines ui.gadgets.charts.axes ;

IN: ui.gadgets.charts.live

TUPLE: live-chart < chart updater { paused initial: f } fft-plot ;
SYMBOL: lines
lines [ H{ } clone ] initialize
SYMBOL: line-colors
line-colors [ H{
            { 0 $ link-color }
            { 1 $ title-color }
            { 2 $ heading-color }
            { 3 $ object-color }
            { 4 $ popup-color }
            { 5 $ retain-stack-color }
            { 6 $ string-color }
            { 7 $ output-color }
        } ] initialize

M: live-chart ungraft* t >>paused drop ;

: calculated-axis-limits ( x y -- x-y-limits )
    [ [ infimum ] [ supremum ] bi 2array ] bi@ 2array ; 

: valid-axis-limits? ( x-y-limits -- ? )
    [ first2 swap - 0.0 = not ] map first2 and ;

: curve-axes ( xy -- x y )
    [ 0 <column> ] [ 1 <column> ] bi ;

: curve-axes-long-enough? ( x y -- ? )
    [ length 1 > ] bi@ and ;

:: update-axis ( gadget data -- )
    data curve-axes
    2dup curve-axes-long-enough?
    [
        calculated-axis-limits
        { [ valid-axis-limits? ]
        [ gadget axes>> = not ] ! check if different to existing
        [ gadget swap >>axes relayout-1 t ] } 1&& drop
    ] [ 2drop ] if ;

: (update-axes) ( axes x-y-limits -- new-axes )
    2array stitch [ first ] [ second ] bi calculated-axis-limits ;

:: update-axes ( axes xy -- new-axes/? )
    xy curve-axes
    2dup curve-axes-long-enough?
    [
        calculated-axis-limits
        dup valid-axis-limits?
        [ axes swap (update-axes) ] when
    ] [ 2drop f ] if ;

:: update-children-axes ( gadget -- )
    gadget children>>
    [
        dup line?
        [
            gadget axes>> swap data>> update-axes [ gadget swap >>axes drop ] when*
        ] [ drop ] if
    ] each ;

:: create-line ( idx gadget -- line )
    line new idx line-colors get at >>color V{ } clone >>data
    [ gadget swap add-gadget drop ] [ [ idx lines get set-at ] keep ] bi ;

:: get-or-create-line ( idx gadget -- line )
    idx lines get at [ idx gadget create-line ] unless* ;

:: plot-rest-against-first ( gadget row -- )
    row <enumerated>
    [ rest ]
    [ first ] bi
    [
        swap
        [ [ second ] bi@ 2array ]
        [ first gadget get-or-create-line data>> ] bi 
        push
    ] curry each ;

:: plot-fft ( gadget row -- )
    row
    <enumerated>
    [ rest ]
    [ first ] bi
    [
        swap
        [ first gadget get-or-create-line data>> curve-axes nip fft [ abs ] map ]
        [ first row length + gadget get-or-create-line swap <enumerated> [ [ 0.1 * ] map ] map >>data drop ] bi 
        drop
    ] curry each ; 

:: plot-custom ( gadget row -- )
    gadget children>>
    [
        dup line?
        [
            [ data>> row swap [ [ second ] [ fourth ] bi 2array ] dip push ]
            [ gadget swap data>> update-axis ]
            [ relayout-1 ] tri ! TODO limit amount of redrawing
        ] [ drop ] if
    ] each ;

:: charting-loop ( gadget -- )
    [ gadget paused>> ]
    [
        gadget updater>> call( -- x/? )
        [
            gadget swap plot-custom
            ! gadget swap plot-rest-against-first gadget [ update-children-axes ] [ relayout-1 ] bi
            ! gadget swap [ plot-rest-against-first ] [ plot-fft ] 2bi gadget [ update-children-axes ] [ relayout-1 ] bi
            yield
        ] when*
    ] until ;

:: start-chart-thread ( gadget -- )
    [
        "file" get
        [ utf8 [ gadget charting-loop ] with-file-reader ]
        [ drop gadget charting-loop ]
        if*
    ] in-thread
    ;

: (live-chart) ( quot -- gadget )
    live-chart new ${ ${ -0.1 0.1 } { -0.1 0.1 } } >>axes swap >>updater
    line new 0 line-colors get at >>color V{ } clone >>data add-gadget
    vertical-axis new text-color >>color add-gadget
    horizontal-axis new text-color >>color add-gadget
    white-interior
    live-chart new ${ ${ -0.1 0.1 } { -0.1 0.1 } } >>axes >>fft-plot
    ;

! don't know why this happens if input stream doesn't get data for a bit
: valid-csv-input? ( seq -- ? ) { "" } = not ;

: inactive-delay ( -- ) 15 milliseconds sleep ;

: csv-live-demo ( -- gadget )
    [ read-row dup valid-csv-input?
        [ [ string>number ] map ] [ drop inactive-delay f ] if
    ] (live-chart) 
    [ start-chart-thread ] keep ;

MAIN-WINDOW: live-chart-window { { title "live-chart" } }
    csv-live-demo >>gadgets ;

