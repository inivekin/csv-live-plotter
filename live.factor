USING: kernel locals channels math.matrices math.transforms.fft threads
ui.gadgets.charts ui.gadgets.labels ui.gadgets.packs ui.gadgets.charts.lines ui.gadgets.charts.axes ;
QUALIFIED-WITH: models.range mr

IN: ui.gadgets.charts.live

TUPLE: live-chart-window < frame chart ;
TUPLE: live-chart < chart { paused initial: f } axes-limits axes-scaling lines series-metadata axes-label-models ;
TUPLE: live-axis-observer quot ;
M: live-axis-observer model-changed
    [ value>> ] dip quot>> call( value -- ) ;
TUPLE: range-observer quot ;
M: range-observer model-changed
    [ range-value ] dip quot>> call( value -- ) ;
TUPLE: live-series-info < pack ;
TUPLE: live-line < line { sample-limit initial: f } ;
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

: com-pause ( gadget -- )
    dup paused>> not >>paused drop ;

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
    lines>> values
    dup length 0 = not
    [
        [ rest ]
        [ first data>> curve-axes 2dup curve-axes-long-enough? [ calculated-axis-limits ] [ 2drop <default-min-axes> ] if
    ] bi
    [ data>> calculate-new-axes ] reduce ] [ drop f ] if ;

:: label-placements ( seq -- seq' )
    seq first2 :> ( x y )
    0 y 2 / 2array
    x 0.95 * y 2 / 2array
    x 2 / y 0.95 * 2array
    x 2 / 0 2array
    4array ;

: series-identifier ( idx -- str )
    number>string ;

: <series-metadata> ( idx -- gadget )
    ! TODO(kevinc) series specific models/stuff added here
    "test" <label> white-interior { 2 2 } <filled-border> swap [ series-identifier ] [ line-colors get at ] bi <framed-labeled-gadget> ;

:: update-children-axes ( gadget -- )
    gadget get-children-axes [ gadget axes-limits>> set-model ] [ <default-min-axes> gadget axes-limits>> set-model ] if*
    gadget [ axes>> concat ] [ axes-label-models>> ] bi zip [ first2 [ number>string ] [ model>> ] bi* set-model ] each
    ! TODO(kevinc) replace with draw-gadget* generic
    gadget [ chart-dim label-placements ] [ axes-label-models>> ] bi zip [ first2 loc<< ] each ;

:: create-line ( idx gadget -- line )
    live-line new idx line-colors get at >>color V{ } clone >>data
    [ gadget swap add-gadget drop ] [ [ idx gadget lines>> set-at ] keep ] bi ;

:: get-or-create-line ( idx gadget -- line )
    idx gadget lines>> at
    [
        idx gadget create-line
        gadget series-metadata>> idx <series-metadata> add-gadget drop
    ] unless* ;

: limit-vector ( seq n -- newseq )
    index-or-length tail* V{ } like ;

: update-live-line ( el idx gadget -- )
    get-or-create-line [ data>> push ] [ dup [ data>> ] [ sample-limit>> ] bi [ limit-vector ] when* >>data drop ] bi ; inline

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

:: multiply-axis ( limits scaling -- scaled-limits )
    limits first2 swap -
    scaling first *

    limits first2 swap -
    scaling second *
    limits first +
    [ + ] keep
    swap 2array ;

: set-chart-axes ( chart -- chart )
    ! dup [ axes-limits>> value>> dup ] [ axes-scaling>> ] bi m* m- >>axes ;
    dup [ axes-limits>> value>> ] [ axes-scaling>> ] bi zip [ [ first ] [ second ] bi multiply-axis ] map >>axes ;

:: <live-chart> ( -- window-gadget )
    3 2 <frame>
    live-chart new <default-min-axes> [ >>axes ] [ add-axis-labels ] bi H{ } clone >>lines { { 1.0 0 } { 1.0 0 } } >>axes-scaling :> lchart
    lchart
    <default-min-axes> <model> [ >>axes-limits ] [ over [ set-chart-axes 2drop ] curry live-axis-observer boa swap add-connection ] bi
    vertical-axis new text-color >>color add-gadget
    horizontal-axis new text-color >>color add-gadget
    white-interior
    { 0 0 } grid-add

    <shelf>
    1.0 0.01 0 1.0 0.01 mr:<range> [ [ lchart axes-scaling>> { 1 0 } swap matrix-set-nth lchart set-chart-axes drop ] range-observer boa swap add-connection ] keep
    vertical <slider>
    { 1 1 } <filled-border> add-gadget
    0 0.01 0 1.0 0.01 mr:<range> [ [ lchart axes-scaling>> { 1 1 } swap matrix-set-nth lchart set-chart-axes drop ] range-observer boa swap add-connection ] keep
    vertical <slider>
    { 1 1 } <filled-border> add-gadget
    white-interior
    1 >>fill
    { 1 0 } grid-add
    <pile>
    1.0 0.01 0 1.0 0.01 mr:<range> [ [ lchart axes-scaling>> { 0 0 } swap matrix-set-nth lchart set-chart-axes drop ] range-observer boa swap add-connection ] keep
    horizontal <slider>
    { 1 1 } <filled-border> add-gadget
    0 0.01 0 1 0.01 mr:<range> [ [ lchart axes-scaling>> { 0 1 } swap matrix-set-nth lchart set-chart-axes drop ] range-observer boa swap add-connection ] keep
    horizontal <slider>
    { 1 1 } <filled-border> add-gadget
    white-interior
    1 >>fill
    { 0 1 } grid-add

    <pile> "pause" [ drop lchart com-pause ] <button> white-interior add-gadget { 2 1 } grid-add

    live-series-info new vertical >>orientation
    white-interior

    [ lchart series-metadata<< ]
    [ { 2 0 } grid-add ]
    bi
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

: start-data-read-thread ( stream quot channel flag -- )
    '[ _
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

: frame-livecharts ( gadget -- seq )
    children>> [ live-chart? ] filter ;

:: csv-plotter ( stream x-column y-columns -- gadget )
    <channel> <live-chart> <flag> :> ( ch g f )
    stream (csv-data-read) ch f start-data-read-thread ! controller
    ch g frame-livecharts first '[ x-column y-columns _ plot-columns ] start-data-update-thread ! model
    f g frame-livecharts first start-data-display-thread ! view
    g
    ;

: csv-plotter-demo. ( -- gadget )
    P" work/csv-stream/testinput.csv" utf8 <file-reader> 1 { 2 3 } csv-plotter ;

MAIN-WINDOW: live-chart-window { { title "live-chart" } }
    "file" get <file-or-stdin-stream>
    "x" get [ string>number ] [ 0 ] if*
    "y" get [ "," split [ string>number ] map ] [ f ] if*
    csv-plotter >>gadgets ;

