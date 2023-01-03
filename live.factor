USING: kernel locals channels math.matrices math.transforms.fft threads
ui.gadgets.charts ui.gadgets.charts.lines ui.gadgets.charts.axes ;

IN: ui.gadgets.charts.live

TUPLE: live-chart < chart { paused initial: f } lines axes-label-models ;
TUPLE: live-line < line { sample-limit initial: 500 } ;
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

:: label-placements ( seq -- seq' )
    seq first2 :> ( x y )
    0 y 2 / 2array
    x 0.95 * y 2 / 2array
    x 2 / y 0.95 * 2array
    x 2 / 0 2array
    4array ;

:: update-children-axes ( gadget -- )
    gadget get-children-axes [ gadget axes<< ] [ <default-min-axes> gadget axes<< ] if*
    gadget [ axes>> concat ] [ axes-label-models>> ] bi zip [ first2 [ number>string ] [ model>> ] bi* set-model ] each
    ! TODO(kevinc) replace with draw-gadget* generic
    gadget [ chart-dim label-placements ] [ axes-label-models>> ] bi zip [ first2 loc<< ] each ;

:: create-line ( idx gadget -- line )
    live-line new idx line-colors get at >>color V{ } clone >>data
    [ gadget swap add-gadget drop ] [ [ idx gadget lines>> set-at ] keep ] bi ;

:: get-or-create-line ( idx gadget -- line )
    idx gadget lines>> at [ idx gadget create-line ] unless* ;

: limit-vector ( seq n -- newseq )
    index-or-length tail* V{ } like ;

: update-live-line ( el idx gadget -- )
    get-or-create-line [ data>> push ] [ dup [ data>> ] [ sample-limit>> ] bi limit-vector >>data drop ] bi ; inline

:: plot-columns ( row x-col y-cols gadget -- )
    row <enumerated>
    [ y-cols [ [ first y-cols in? ] filter ] [ x-col swap remove-nth ] if ]
    [ x-col swap nth ] bi
    [
        swap
        [ [ second ] bi@ 2array ]
        [ first gadget update-live-line ] bi 
    ] curry each ;

:: add-axis-labels ( gadget axes -- gadget )
    axes concat
    [ <model> [ number>string ] <arrow> <label-control> ] map [ [ gadget swap add-gadget drop ] each ] [ gadget axes-label-models<< ] bi 
    gadget ;

: <live-chart> ( -- gadget )
    live-chart new <default-min-axes> [ >>axes ] [ add-axis-labels ] bi H{ } clone >>lines
    vertical-axis new text-color >>color add-gadget
    horizontal-axis new text-color >>color add-gadget
    white-interior
    ;

! don't know why this happens if input stream doesn't get data for a bit
: valid-csv-input? ( seq -- ? ) { "" } = not ;

: inactive-delay ( -- ) 15 milliseconds sleep ;

: (csv-data-read) ( -- quot )
    [ read-row dup valid-csv-input?
        [ [ string>number ] map ] [ drop inactive-delay f ] if
    ] ; 

: <file-or-stdin-stream> ( filepath/? -- stream )
    [ utf8 <file-reader> ] [ input-stream get ] if* ;

: start-data-read-thread ( filepath/? quot channel flag -- )
    '[ _ <file-or-stdin-stream>
        [ [ _ call( -- seq/? ) [ _ to _ raise-flag ] when* t ] loop ] with-input-stream
    ] in-thread ;

: start-data-update-thread ( channel quot -- )
    '[ [ _ from ] [ _ call( seq -- ) ] while* ] in-thread ;

:: start-data-display-thread ( flag gadget -- )
    [
        [ flag [ wait-for-flag ] [ lower-flag ] bi gadget paused>> ]
        [ gadget [ update-children-axes ] [ relayout-1 ] bi 16 milliseconds sleep ]
        until
    ] in-thread ;

:: csv-plotter ( filepath/? x-column y-columns -- gadget )
    <channel> <live-chart> <flag> :> ( ch g f )
    filepath/? (csv-data-read) ch f start-data-read-thread ! controller
    ch [ x-column y-columns g plot-columns ] start-data-update-thread ! model
    f g start-data-display-thread ! view
    g
    ;

MAIN-WINDOW: live-chart-window { { title "live-chart" } }
    "file" get
    "x" get [ string>number ] [ 0 ] if*
    "y" get [ "," split [ string>number ] map ] [ f ] if*
    csv-plotter >>gadgets ;

