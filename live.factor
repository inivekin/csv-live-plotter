USING: kernel locals channels math.matrices math.transforms.fft threads
ui.gadgets.charts ui.gadgets.labels ui.gadgets.packs ui.gadgets.charts.lines
ui.gadgets.charts.axes ui.gadgets.charts.utils ;
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
TUPLE: live-line < line { sample-limit initial: f } axes-limits cursor-axes ;
TUPLE: live-cursor-vertical-axis < axis center ;
TUPLE: live-cursor-horizontal-axis < axis center ;

M: live-cursor-vertical-axis draw-gadget*
    dup parent>> dup live-line? [| axis lline |
        axis center>> dup
        [
            second
            lline parent>> dim>> second swap
            lline parent>> axes-limits>> value>> second first2
            scale
            [ 0 swap 2array ] [ lline parent>> dim>> first swap 2array ] bi 2array draw-line
        ]
        [
            drop
        ] if
    ] [ 2drop ] if ;

M: live-cursor-horizontal-axis draw-gadget*
    dup parent>> dup live-line? [| axis lline |
        axis center>> dup
        [
            first
            lline parent>> dim>> first swap
            lline parent>> axes-limits>> value>> first first2 swap
            scale
            [ 0 2array ] [ lline parent>> dim>> second 2array ] bi 2array draw-line
        ]
        [
            drop
        ] if
    ] [ 2drop ] if ;
    

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
    { { -0.1 0.1 } { -0.1 0.1 } } ;

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

:: mutate-new-axes ( lines xy -- )
    xy curve-axes 
    2dup curve-axes-long-enough?
    [
        calculated-axis-limits
        dup valid-axis-limits?
        [
            lines axes-limits>> set-model
            f
        ] when
        drop
    ]
    [
        2drop
    ] if
    ;

: series-identifier ( idx -- str )
    number>string ;

:: change-cursor ( ratio idx line -- )
    line parent>> dim>> :> dim
    line data>> [ length ratio * round >integer ] [ nth ] bi :> limits
    line cursor-axes>> first2 [ limits >>center ] bi@
    2drop
    ;

:: <series-metadata> ( line idx -- gadget )
    ! TODO(kevinc) series specific models/stuff added here

    2 6 <frame>
    "test" <label> white-interior { 2 2 } <filled-border> { 0 0 } grid-add
    ""  <label> white-interior { 1 0 } grid-add
    "ymin: " <label> white-interior { 0 1 } grid-add
    line axes-limits>> [ second first "%.3f" sprintf ] <arrow> <label-control> white-interior { 1 1 } grid-add
    "ymax: " <label> white-interior { 0 2 } grid-add
    line axes-limits>> [ second second "%.3f" sprintf ] <arrow> <label-control> white-interior { 1 2 } grid-add
    "xmin: " <label> white-interior { 0 3 } grid-add
    line axes-limits>> [ first first "%.3f" sprintf ] <arrow> <label-control> white-interior { 1 3 } grid-add
    "xmax: " <label> white-interior { 0 4 } grid-add
    line axes-limits>> [ first second "%.3f" sprintf ] <arrow> <label-control> white-interior { 1 4 } grid-add

    "cursor: " <label> white-interior { 0 5 } grid-add
    0 0.01 0 1 0.01 mr:<range> [ [ idx line change-cursor ] range-observer boa swap add-connection ] keep
    horizontal <slider>
    { 1 5 } grid-add

    idx [ series-identifier ] [ line-colors get at ] bi <framed-labeled-gadget>
    ;

:: add-cursor-axes-to-line ( line idx -- )
    live-cursor-vertical-axis new live-cursor-horizontal-axis new
    [ idx line-colors get at >>color ] bi@

    [ line swap add-gadget swap add-gadget drop ]
    [ 2array line swap >>cursor-axes ]
    2bi
    drop
    ;

:: create-line ( idx gadget -- line )
    live-line new idx line-colors get at >>color V{ } clone >>data
    [ gadget swap add-gadget drop ] [ [ idx gadget lines>> set-at ] keep ] bi
    <default-min-axes> <model> >>axes-limits
    ! dup idx add-cursor-axes-to-line
    ;

:: get-or-create-line ( idx gadget -- line )
    idx gadget lines>> at
    [
        idx gadget create-line :> l
        gadget series-metadata>> l idx <series-metadata> add-gadget drop
        l
        dup idx add-cursor-axes-to-line
    ] unless* ;

! best not to use the default in case the max and min of default is
! somehow a larger range than the actual data
: default-axes ( line-values -- axes )
    first data>> curve-axes 2dup curve-axes-long-enough? 
    [ calculated-axis-limits ] [ 2drop <default-min-axes> ] if
    ;

: get-children-axes ( gadget -- seq/? )
    lines>> values
    dup length 0 = not
    [
        [ rest ] [ default-axes ] bi
        [ data>> calculate-new-axes ] reduce
    ] [ drop f ] if ;


:: update-children-axes ( gadget -- seq/? )
    gadget lines>> unzip :> ( l v )
    v length 0 = not
    [
        l v [ [ gadget get-or-create-line ] [ data>> ] bi* mutate-new-axes ] 2each
        v [ rest ] [ default-axes ] bi
        [ axes-limits>> value>> swap (calculate-axes) ] reduce
    ] [ f ] if ;

:: update-all-axes ( gadget -- )
    ! gadget get-children-axes [ gadget axes-limits>> set-model ] [ <default-min-axes> gadget axes-limits>> set-model ] if*
    gadget update-children-axes [ gadget axes-limits>> set-model ] [ <default-min-axes> gadget axes-limits>> set-model ] if*
    ! NOT NEEDED? gadget [ axes>> concat ] [ axes-label-models>> ] bi zip [ first2 [ number>string ] [ model>> ] bi* set-model ] each
    ;

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
    [ <model> [ number>string ] <arrow> <label-control> ] map
    [ [ gadget swap add-gadget drop ] each ] [ gadget axes-label-models<< ] bi 
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
        f swap [ in? ] keep swap [ drop f ] when
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
        [ gadget [ update-all-axes ] [ relayout-1 ] bi 16 milliseconds sleep ]
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

