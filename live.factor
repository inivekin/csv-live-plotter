USING: kernel locals channels math.matrices math.transforms.fft threads
ui.gadgets.charts ui.gadgets.charts.lines ui.gadgets.charts.axes ;

IN: ui.gadgets.charts.live

TUPLE: live-chart < chart { paused initial: f } ;
TUPLE: live-line < line { sample-limit initial: 500 } ;
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

: <default-min-axes> ( -- seq )
    ${ ${ -0.1 0.1 } { -0.1 0.1 } } ;

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

: (calculate-axes) ( axes x-y-limits -- new-axes )
    2array stitch [ first ] [ second ] bi calculated-axis-limits ;

:: calculate-new-axes ( axes xy -- new-axes/? )
    xy curve-axes
    2dup curve-axes-long-enough?
    [
        calculated-axis-limits
        dup valid-axis-limits?
        [ axes swap (calculate-axes) ] when
    ] [ 2drop f ] if ;

: get-children-axes ( gadget -- seq/? )
    children>> [ line? ] filter
    dup length 0 = not [ [ rest ] [ first data>> curve-axes 2dup curve-axes-long-enough? [ calculated-axis-limits ] [ 2drop <default-min-axes> ] if ] bi [ data>> calculate-new-axes ] reduce ] [ drop f ] if ;

:: update-children-axes ( gadget -- )
    gadget get-children-axes [ gadget axes<< ] [ <default-min-axes> gadget axes<< ] if* ;

:: create-line ( idx gadget -- line )
    live-line new idx line-colors get at >>color V{ } clone >>data
    [ gadget swap add-gadget drop ] [ [ idx lines get set-at ] keep ] bi ;

:: get-or-create-line ( idx gadget -- line )
    idx lines get at [ idx gadget create-line ] unless* ;

: limit-vector ( seq n -- newseq )
    index-or-length tail* V{ } like ;

: update-live-line ( el gadget -- )
    get-or-create-line [ data>> push ] [ dup [ data>> ] [ sample-limit>> ] bi limit-vector >>data drop ] bi ; inline

:: plot-rest-against-first ( row gadget -- )
    row <enumerated>
    [ rest ]
    [ first ] bi
    [
        swap
        [ [ second ] bi@ 2array ]
        [ first gadget update-live-line ] bi 
    ] curry each ;

: plot-columns ( row x-col y-col gadget -- )
    [ 2array swap [ nth ] curry map ]
    [ 0 swap update-live-line ] bi* ;

: <live-chart> ( -- gadget )
    live-chart new <default-min-axes> >>axes
    vertical-axis new text-color >>color add-gadget
    horizontal-axis new text-color >>color add-gadget
    white-interior
    ;

! don't know why this happens if input stream doesn't get data for a bit
: valid-csv-input? ( seq -- ? ) { "" } = not ;

: inactive-delay ( -- ) 15 milliseconds sleep ;

! : (csv-data-read) ( -- quot( -- seq ) )
: (csv-data-read) ( -- quot )
    [ read-row dup valid-csv-input?
        [ [ string>number ] map ] [ drop inactive-delay f ] if
    ] ; 

: <file-or-stdin-stream> ( -- stream )
    "file" get [ utf8 <file-reader> ] [ input-stream get ] if* ;

! : start-data-read-thread ( stream quot( seq -- seq ) channel -- )
: start-data-read-thread ( quot channel flag -- )
    '[ <file-or-stdin-stream>
        [ [ _ call( -- seq/? ) [ _ to _ raise-flag ] when* t ] loop ] with-input-stream
    ] in-thread ;

! : start-data-update-thread ( channel quot( seq -- ) -- )
: start-data-update-thread ( channel quot -- )
    '[ [ _ from ] [ _ call( seq -- ) ] while* ] in-thread ;

:: start-data-display-thread ( flag gadget -- )
    [
        [ flag [ wait-for-flag ] [ lower-flag ] bi gadget paused>> ]
        [ gadget [ update-children-axes ] [ relayout-1 ] bi 16 milliseconds sleep ]
        until
    ] in-thread ;

:: csv-plotter ( -- gadget )
    <channel> <live-chart> <flag> :> ( ch g f )
    (csv-data-read) ch f start-data-read-thread ! controller
    ch [ g plot-rest-against-first ] start-data-update-thread ! model
    ! ch [ 1 3 g plot-columns ] start-data-update-thread ! model
    f g start-data-display-thread ! view
    g
    ;

MAIN-WINDOW: live-chart-window { { title "live-chart" } }
    csv-plotter >>gadgets ;

