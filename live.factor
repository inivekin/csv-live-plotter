USING: accessors arrays assocs calendar channels colors columns
concurrency.flags csv formatting io io.encodings.utf8 io.files
io.streams.duplex kernel literals locals math math.functions
math.matrices math.order math.parser math.transforms.fft models
models.arrow models.range namespaces sequences serialize sets
splitting threads ui ui.gadgets ui.gadgets.borders
ui.gadgets.buttons ui.gadgets.charts ui.gadgets.charts.axes
ui.gadgets.charts.lines ui.gadgets.charts.utils
ui.gadgets.frames ui.gadgets.grids ui.gadgets.labeled
ui.gadgets.labels ui.gadgets.packs ui.gadgets.scrollers
ui.gadgets.sliders ui.gestures ui.pens.gradient  ui.pens.solid
ui.render ui.theme ui.theme.base16 ui.theme.switching
ui.tools.common vectors ;
QUALIFIED-WITH: models.range mr
FROM: namespaces => set ;
IN: ui.gadgets.charts.live

INITIALIZED-SYMBOL: sample-sequence [ f ]
INITIALIZED-SYMBOL: sample-limit [ f ]

! TODO add interface for dynamic configuring sample-limit for streaming data
! TODO generate colours when above 7 limit
! TODO toggle visibility?

TUPLE: live-chart-window < frame chart ;
TUPLE: live-chart < chart { paused initial: f } axes-limits axes-labels axes-scaling { headers initial: f } lines series-metadata latest-zoom-start latest-zoom-end zoom-axes xs ys ;
TUPLE: live-axis-observer quot ;
M: live-axis-observer model-changed
    [ value>> ] dip quot>> call( value -- ) ;
TUPLE: range-observer quot ;
M: range-observer model-changed
    [ range-value ] dip quot>> call( value -- ) ;
TUPLE: live-series-info < pack ;
TUPLE: live-line < line { name initial: "unnamed" } { sample-limit initial: f } axes-limits { cursor-axes initial: V{ } } { cursors initial: V{ } } ;
TUPLE: live-cursor-vertical-axis < axis center ;
TUPLE: live-cursor-horizontal-axis < axis center ;

M: live-cursor-vertical-axis draw-gadget*
    dup parent>> dup live-line? [| axis lline |
        axis center>> value>>
        [
            second
            lline parent>> dim>> second

            swap
            lline parent>> axes-limits>> value>> second first2 swap
            scale

            lline parent>> dim>> second swap -
            [ 0 swap 2array ] [ lline parent>> dim>> first swap 2array ] bi 2array draw-line
        ] when*
    ] [ 2drop ] if ;

M: live-cursor-horizontal-axis draw-gadget*
    dup parent>> dup live-line? [| axis lline |
        axis center>> value>>
        [
            first
            lline parent>> dim>> first

            swap
            lline parent>> axes-limits>> value>> first first2 swap
            scale

            [ 0 2array ] [ lline parent>> dim>> second 2array ] bi 2array draw-line
        ] when*
    ] [ 2drop ] if ;
    
INITIALIZED-SYMBOL: line-colors
[ H{
    { 0 $ heading-color }
    { 1 $ errors-color }
    { 2 $ title-color }
    { 3 $ link-color }
    { 4 $ object-color }
    { 5 $ popup-color }
    { 6 $ retain-stack-color }
    { 7 $ output-color }
} ]

M: live-chart ungraft* t >>paused drop ;

: com-pause ( button gadget -- )
    dup paused>> not [ >>paused drop ] keep [ details-color <solid> >>interior drop ] [ content-background <solid> >>interior drop ] if ;

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
    line data>> [ length ratio 100 /f * round >integer 0 line data>> length 1 - clamp ] [ nth ] bi :> limits
    idx line cursor-axes>> at first2 [ center>> limits swap set-model ] bi@
    ;

:: <cursor> ( line idx -- cursor )
    2 3 <frame>
    ! "cursor: " <label> white-interior { 0 0 } grid-add
    0 1 0 100 1 mr:<range> [ [ idx line change-cursor ] range-observer boa swap add-connection ] keep
    horizontal <slider>
    { 0 0 } grid-add
    "xcursor: " <label> white-interior { 0 1 } grid-add
    idx line cursor-axes>> at first center>> [ [ first "%.3f" sprintf ] [ "f" sprintf ] if* ] <arrow> <label-control> white-interior { 1 1 } grid-add
    "ycursor: " <label> white-interior { 0 2 } grid-add
    idx line cursor-axes>> at first center>> [ [ second "%.3f" sprintf ] [ "f" sprintf ] if* ] <arrow> <label-control> white-interior { 1 2 } grid-add
    ;

:: <metadata> ( line idx -- metadata )
    2 4 <frame>
    "ymin: " <label> white-interior { 0 0 } grid-add
    line axes-limits>> [ second first "%.3f" sprintf ] <arrow> <label-control> white-interior { 1 0 } grid-add
    "ymax: " <label> white-interior { 0 1 } grid-add
    line axes-limits>> [ second second "%.3f" sprintf ] <arrow> <label-control> white-interior { 1 1 } grid-add
    "xmin: " <label> white-interior { 0 2 } grid-add
    line axes-limits>> [ first first "%.3f" sprintf ] <arrow> <label-control> white-interior { 1 2 } grid-add
    "xmax: " <label> white-interior { 0 3 } grid-add
    line axes-limits>> [ first second "%.3f" sprintf ] <arrow> <label-control> white-interior { 1 3 } grid-add
    ;

:: add-cursor-axes-to-line ( line idx -- )
    live-cursor-vertical-axis new live-cursor-horizontal-axis new
    [ idx line-colors get at >rgba-components drop 0.5 <rgba> >>color f <model> >>center ] bi@

    [ line swap add-gadget swap add-gadget drop ]
    [ 2array line cursors>> length line cursor-axes>> set-at ]
    2bi
    ;

:: <series-metadata> ( line idx -- gadget )
    <pile>
    line name>> <label> { 2 2 } <filled-border> add-gadget
    line idx <metadata> add-gadget
    "add cursor" [ line idx add-cursor-axes-to-line parent>> line dup cursors>> length <cursor> [ add-gadget drop ] [ line cursors>> push ] bi ] <roll-button> add-gadget

    idx [ series-identifier ] [ line-colors get at ] bi <framed-labeled-gadget>
    ;


:: create-line ( idx gadget -- line )
    live-line new idx line-colors get at >>color V{ } clone >>data
    sample-limit get >>sample-limit
    [ gadget swap add-gadget drop ] [ [ idx gadget lines>> set-at ] keep ] bi
    <default-min-axes> <model> >>axes-limits
    dup idx add-cursor-axes-to-line
    ;

:: get-or-create-line ( idx gadget -- line )
    idx gadget lines>> at
    [
        idx gadget create-line :> l
        gadget headers>> [ idx swap nth l swap >>name drop ] when*
        gadget series-metadata>> l idx <series-metadata> add-gadget drop
        l
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
    gadget update-children-axes
    [ gadget axes-limits>> set-model ]
    [ <default-min-axes> gadget axes-limits>> set-model ]
    if*
    ;

: limit-vector ( seq n -- newseq )
    index-or-length tail* V{ } like ;

: update-live-line ( el idx gadget -- )
    get-or-create-line
    [ data>> push ]
    [ dup [ data>> ] [ sample-limit>> ] bi [ limit-vector ] when* >>data drop ]
    bi ; inline

:: plot-columns ( row x-col y-cols gadget -- )
    row <enumerated>
    [ y-cols [ [ first y-cols in? ] filter ] [ x-col [ swap remove-nth ] when* ] if ]
    [ x-col [ swap nth ] [ sample-sequence get sample-sequence inc 2array ] if* ] bi
    [
        swap
        [ [ second ] bi@ 2array ]
        [ first gadget update-live-line ] bi 
    ] curry each ;

:: multiply-axis ( limits scaling -- scaled-limits )
    limits first2 swap -
    scaling first *

    limits first2 swap -
    scaling second *
    limits first +
    [ + ] keep
    swap 2array ;

: set-chart-axes ( chart -- chart )
    [ dup [ axes-limits>> value>> ] [ axes-scaling>> ] bi zip [ [ first ] [ second ] bi multiply-axis ] map ] keep
    '[ _ axes-labels>> set-model ] [ >>axes ] bi ;

:: <live-chart> ( headers flag -- window-gadget )
    2 2 <frame> white-interior
    live-chart new <default-min-axes> >>axes H{ } clone >>lines { { 1.0 0 } { 1.0 0 } } >>axes-scaling :> lchart
    lchart headers >>headers
    <default-min-axes> <model> >>axes-labels 
    <default-min-axes> <model> [ >>axes-limits ] [ over [ set-chart-axes 2drop ] curry live-axis-observer boa swap add-connection ] bi
    vertical-axis new text-color >>color add-gadget
    horizontal-axis new text-color >>color add-gadget
    white-interior
    { 0 0 } grid-add

    <pile> "pause" [ lchart com-pause flag raise-flag ] <roll-button> white-interior add-gadget { 1 1 } grid-add

    lchart axes-labels>> [ first2 [ first2 ] bi@ "g_xmin: %.3f g_xmax: %.3f g_ymin: %.3f g_ymax: %.3f" sprintf ] <arrow> <label-control> { 0 1 } grid-add

    live-series-info new vertical >>orientation
    white-interior

    [ lchart series-metadata<< ]
    [ <scroller> { 1 0 } grid-add ]
    bi
    ;

! don't know why this happens if input stream doesn't get data for a bit
: valid-csv-input? ( seq -- ? ) { "" } = not ;

: inactive-delay ( -- ) 16 milliseconds sleep ;

: (csv-data-read) ( -- quot )
    [ read-row dup valid-csv-input?
        [ [ string>number ] map ] [ drop yield inactive-delay f ] if
        f swap [ in? ] keep swap [ drop f ] when
    ] ;

: (data-feeder) ( rows -- quot )
    <reversed> >vector '[ _ pop [ f sleep-until ] unless* ] ;

:: insert-by-key ( row x-key keys -- row' )
    1 row col keys zip
    1 keys [ maximum ] [ 1 row col length ] if* 1 + <zero-matrix> first
    [ '[ first2 _ set-nth ] each ] keep
    x-key [ [ [ row first first x-key ] dip set-nth ] keep ] when
    ;

: (line-feeder) ( x-key y-keys rows -- quot )
    <reversed> >vector -rot
    '[ _ dup empty? [ drop f ] [ pop [ _ _ insert-by-key ] [ f sleep-until ] if* ] if ] ;

: <file-or-stdin-stream> ( filepath/? -- stream )
    [ utf8 <file-reader> ] [ input-stream get ] if* ;

: start-stream-read-thread ( stream quot channel flag -- )
    '[ _
        [
            [ _ call( -- seq/? ) [ _ to _ raise-flag ] when* yield t ] loop
        ] with-input-stream
    ] in-thread ;

: start-data-read-thread ( quot channel flag -- )
    '[
        [ _ call( -- seq/? ) [ _ to _ raise-flag ] [ 16 milliseconds sleep ] if* yield t ] loop
    ] in-thread ;

: start-data-update-thread ( channel quot -- )
    '[ [ _ from ] [ _ call( seq -- ) ] while* f sleep-until ] in-thread ;

:: start-data-display-thread ( flag gadget -- )
    [
      [
        [ 16 milliseconds sleep gadget paused>> dup [ flag lower-flag ] when ]
        [ gadget [ update-all-axes ] [ relayout-1 ] bi ]
        until
        yield
        t
      ] loop
    ] in-thread ;

: frame-livecharts ( gadget -- seq )
    children>> [ live-chart? ] filter ;

! dense matrix opposed to seq-plotter sparse matrix
:: zoom-plotter ( lines x-column y-columns headers -- gadget )
    <channel> headers <flag> [ <live-chart> ] keep :> ( ch g f )
    x-column g { 0 0 } grid-child xs<<
    y-columns g { 0 0 } grid-child ys<<
    x-column y-columns lines (line-feeder) ch f start-data-read-thread ! controller
    ch g frame-livecharts first '[ x-column y-columns _ plot-columns ] sample-sequence get [ 0 ] unless* sample-sequence [ start-data-update-thread ] with-variable ! model
    f g frame-livecharts first start-data-display-thread ! view
    g
    ;

:: seq-plotter ( rows x-column y-columns headers -- gadget )
    <channel> headers <flag> [ <live-chart> ] keep :> ( ch g f )
    x-column g { 0 0 } grid-child xs<<
    y-columns g { 0 0 } grid-child ys<<
    rows (data-feeder) ch f start-data-read-thread ! controller
    ch g frame-livecharts first '[ x-column y-columns _ plot-columns ] sample-sequence get [ 0 ] unless* sample-sequence [ start-data-update-thread ] with-variable ! model
    f g frame-livecharts first start-data-display-thread ! view
    g
    ;

:: csv-plotter ( stream x-column y-columns -- gadget )
    stream [ io:readln "," split ] with-input-stream* :> headers
    <channel> headers <flag> [ <live-chart> ] keep :> ( ch g f )
    x-column g { 0 0 } grid-child xs<<
    y-columns g { 0 0 } grid-child ys<<
    stream (csv-data-read) ch f start-stream-read-thread ! controller
    ch g frame-livecharts first '[ x-column y-columns _ plot-columns ] sample-sequence get [ 0 ] unless* sample-sequence [ start-data-update-thread ] with-variable ! model
    f g frame-livecharts first start-data-display-thread ! view
    g
    ;

: csv-plotter-demo. ( -- gadget )
    ! P" work/csv-stream/testinput.csv" utf8 <file-reader> 1 { 2 3 } csv-plotter ;
    P" extra/machine-learning/data-sets/iris.csv" utf8 <file-reader> 1 { 2 3 } csv-plotter ;

MAIN-WINDOW: live-chart-window { { title "live-chart" } }
    "file" get <file-or-stdin-stream>
    "x" get [ string>number ] [ f ] if*
    "y" get [ "," split [ string>number ] map ] [ f ] if*
    "l" get [ string>number ] [ f ] if*
    sample-limit [ csv-plotter ] with-variable >>gadgets ;

:: begin-chart-zoom ( lchart -- )
  lchart latest-zoom-start>> [ center>> f swap set-model ] when*
  lchart latest-zoom-start>> lchart latest-zoom-end>> [ lchart lines>> values first remove-gadget ] bi@

  lchart axes-limits>> value>> first first2 :> ( xmin xmax )
  lchart hand-rel first lchart dim>> first /
  xmax xmin -
  *
  live-cursor-horizontal-axis new [ swap 0 2array <model> >>center details-color <solid> >>color ] [ lchart lines>> values first swap add-gadget drop ] bi
  lchart latest-zoom-start<<
  ;

:: finish-chart-zoom ( lchart -- )
  ! lchart headers>> <live-chart>
  ! lchart lines>> H{ } assoc-clone-like dup keys swap H{ } clone [ '[ [ _ at [ lchart latest-zoom-start>> floor lchart latest-zoom-end>> ceiling ] dip [ data>> <slice> ] keep swap deep-clone >>data ] [ _ set-at ] bi ] each ] keep
  ! over { 0 0 } grid-child [ lines<< ] [ update-all-axes ] [ relayout-1 ] tri
  ! "zoom" open-window

  lchart axes-limits>> value>> first first2 :> ( xmin xmax )

  lchart latest-zoom-start>> center>> value>> first :> range-start
  lchart latest-zoom-end>> center>> value>> first :> range-end
  lchart lines>> values first data>> length :> x-element-count
  range-start xmax xmin - /f x-element-count * floor >fixnum :> idx-start
  range-end xmax xmin - /f x-element-count * ceiling >fixnum :> idx-end

  lchart lines>> dup keys
  swap '[ _ at [ idx-start idx-end 2dup > [ swap ] when ] dip data>> <slice> ] map flip
  lchart xs>>
  lchart ys>>
  lchart headers>> xmin range-start + sample-sequence [ zoom-plotter [ "zoom" open-window ] [ { 0 0 } grid-child update-all-axes ] [ relayout-1 ] tri ] with-variable  ;

:: highlight-chart-zoom ( lchart -- )
  lchart latest-zoom-start>> center>> value>> first
  lchart axes-limits>> value>> first first2 :> ( xmin xmax )
  drag-loc first lchart dim>> first /f xmax xmin - *
  +
  lchart latest-zoom-end>>
  [
    [ swap 0 2array swap center>> set-model ] keep dup relayout-1
  ]
  [
    live-cursor-horizontal-axis new [ swap 0 2array <model> >>center details-color <solid> >>color ] [ lchart lines>> values first swap add-gadget drop ] bi
  ] if*
  lchart latest-zoom-end<<
  ;

live-chart H{
    { T{ button-down } [ begin-chart-zoom ] }
    { T{ button-up } [ finish-chart-zoom ] }
    { T{ drag } [ highlight-chart-zoom ] }
} set-gestures
