import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Mermaid theme options matching the official mermaid.js themes.
enum MermaidTheme {
  /// Light theme (default).
  light('default'),

  /// Dark theme.
  dark('dark'),

  /// Neutral grey theme.
  neutral('neutral'),

  /// Green forest theme.
  forest('forest');

  const MermaidTheme(this.jsName);

  /// The theme name as expected by mermaid.js `initialize()`.
  final String jsName;
}

/// Renders a Mermaid diagram using the official mermaid.js library in a
/// WebView, providing full-fidelity rendering of all diagram types.
///
/// Each instance creates a small WebView that loads the mermaid.js library
/// and renders the diagram source. The widget auto-sizes its height to fit
/// the rendered diagram.
///
/// Supported diagram types include flowchart, sequence, class, state, ER,
/// pie, gantt, timeline, kanban, mindmap, xychart, radar, gitGraph,
/// journey, quadrant, and any future types added to mermaid.js.
class MermaidWebView extends StatefulWidget {
  const MermaidWebView({
    super.key,
    required this.source,
    this.theme = MermaidTheme.light,
    this.backgroundColor,
    this.onError,
    this.minHeight = 60,
    this.maxHeight = 2000,
  });

  /// The Mermaid diagram source code (without fence markers).
  final String source;

  /// The mermaid rendering theme.
  final MermaidTheme theme;

  /// Background color for the diagram area. Defaults to white/transparent.
  final Color? backgroundColor;

  /// Called when mermaid.js fails to render the diagram.
  final ValueChanged<String>? onError;

  /// Minimum height before auto-sizing kicks in.
  final double minHeight;

  /// Maximum allowed height to prevent unbounded growth.
  final double maxHeight;

  @override
  State<MermaidWebView> createState() => _MermaidWebViewState();
}

class _MermaidWebViewState extends State<MermaidWebView> {
  InAppWebViewController? _controller;
  InAppWebViewInitialData? _initialData;
  late final Key _webViewKey = UniqueKey();
  double _height = 200;
  bool _loading = true;
  bool _pageReady = false;
  bool _platformAvailable = true;
  String? _error;

  /// Cached mermaid.min.js source loaded once from the bundled asset.
  static String? _mermaidJs;

  /// Whether flutter_inappwebview is supported on this platform.
  ///
  /// flutter_inappwebview supports: Android, iOS, macOS, Windows, Linux, Web.
  /// Note: Linux support requires WPE WebKit to be installed on the system.
  static bool get _isWebViewSupported {
    if (kIsWeb) return true;
    return Platform.isAndroid ||
        Platform.isIOS ||
        Platform.isMacOS ||
        Platform.isWindows ||
        Platform.isLinux;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_initWebView());
  }

  @override
  void didUpdateWidget(MermaidWebView old) {
    super.didUpdateWidget(old);
    final bgChanged = old.backgroundColor != widget.backgroundColor;
    if (bgChanged) {
      _updateBackground();
    }
    if (old.source != widget.source || old.theme != widget.theme || bgChanged) {
      _renderDiagram();
    }
  }

  /// Update the HTML body background via JavaScript when the Flutter
  /// background color changes (e.g. dark ↔ light theme switch).
  void _updateBackground() {
    if (_controller == null) return;
    final bgColor = widget.backgroundColor ?? Colors.white;
    final r = (bgColor.r * 255.0).round().clamp(0, 255);
    final g = (bgColor.g * 255.0).round().clamp(0, 255);
    final b = (bgColor.b * 255.0).round().clamp(0, 255);
    final hex =
        '#${r.toRadixString(16).padLeft(2, '0')}'
        '${g.toRadixString(16).padLeft(2, '0')}'
        '${b.toRadixString(16).padLeft(2, '0')}';
    unawaited(
      _controller!.evaluateJavascript(
        source: 'document.body.style.background=${jsonEncode(hex)};',
      ),
    );
  }

  Future<void> _initWebView() async {
    if (!_isWebViewSupported) {
      if (mounted) {
        setState(() {
          _platformAvailable = false;
          _loading = false;
        });
      }
      return;
    }

    try {
      // Load mermaid.js from bundled asset once and cache it.
      _mermaidJs ??= await rootBundle.loadString(
        'packages/tom_mermaid_view/assets/js/mermaid.min.js',
      );

      // Keep a stable initialData instance so platform-view updates don't
      // repeatedly call loadData while the page is still loading.
      _initialData ??= InAppWebViewInitialData(
        data: _buildHtml(_mermaidJs!),
        mimeType: 'text/html',
        encoding: 'utf-8',
      );

      if (mounted) {
        setState(() {
          // Mark that initialization is ready for the build phase.
        });
      }
    } catch (e, st) {
      // Asset missing or other error.
      debugPrint('[MermaidWebView] init failed: $e\n$st');
      if (mounted) {
        setState(() {
          _platformAvailable = false;
          _loading = false;
        });
      }
    }
  }

  void _onWebViewCreated(InAppWebViewController controller) {
    _controller = controller;

    // Add JavaScript handler for messages from the diagram.
    controller.addJavaScriptHandler(
      handlerName: 'MermaidChannel',
      callback: (args) {
        if (args.isNotEmpty) {
          _onMessage(args[0].toString());
        }
        return null;
      },
    );
  }

  void _onLoadStop(InAppWebViewController controller, WebUri? url) {
    _pageReady = true;
    debugPrint('[MermaidWebView] onLoadStop url=$url');
    _renderDiagram();
  }

  void _onMessage(String message) {
    Map<String, dynamic> data;
    try {
      data = jsonDecode(message) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final type = data['type'] as String?;
    if (type == null) return;

    if (type == 'rendered') {
      debugPrint('[MermaidWebView] message=rendered payload=$data');
      final height = (data['height'] as num).toDouble();
      if (mounted) {
        setState(() {
          _height = height.clamp(widget.minHeight, widget.maxHeight);
          _loading = false;
          _error = null;
        });
      }
    } else if (type == 'error') {
      final msg = data['message'] as String;
      debugPrint('[MermaidWebView] message=error error=$msg');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = msg;
        });
      }
      widget.onError?.call(msg);
    } else if (type == 'scroll') {
      final deltaY = (data['deltaY'] as num).toDouble();
      final scrollable = Scrollable.maybeOf(context);
      if (scrollable != null) {
        final pos = scrollable.position;
        pos.jumpTo(
          (pos.pixels + deltaY).clamp(
            pos.minScrollExtent,
            pos.maxScrollExtent,
          ),
        );
      }
    }
  }

  void _renderDiagram() {
    if (!_pageReady || _controller == null) return;
    debugPrint(
      '[MermaidWebView] render start theme=${widget.theme.jsName} sourceLen=${widget.source.length}',
    );
    if (!_loading || _error != null) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    // JSON-encode the source to safely pass it into JavaScript,
    // preventing injection of arbitrary JS through diagram source.
    final escapedSource = jsonEncode(widget.source);
    final themeName = widget.theme.jsName;
    unawaited(
      _controller!.evaluateJavascript(
        source: 'renderMermaid($escapedSource, ${jsonEncode(themeName)});',
      ),
    );
  }

  String _buildHtml(String mermaidJs) {
    final bgColor = widget.backgroundColor ?? Colors.white;
    final r = (bgColor.r * 255.0).round().clamp(0, 255);
    final g = (bgColor.g * 255.0).round().clamp(0, 255);
    final b = (bgColor.b * 255.0).round().clamp(0, 255);
    final bgHex =
        '#${r.toRadixString(16).padLeft(2, '0')}'
        '${g.toRadixString(16).padLeft(2, '0')}'
        '${b.toRadixString(16).padLeft(2, '0')}';

    return '''<!DOCTYPE html>
<html><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<script>$mermaidJs</script>
<style>
*{margin:0;padding:0;box-sizing:border-box}
html,body{overflow:hidden;background:$bgHex;font-family:sans-serif}
#diagram{padding:8px}
#diagram svg{display:block;max-width:100%;height:auto}
.error{color:#d32f2f;font-family:monospace;font-size:12px;padding:8px}
/* Dark-mode CSS overrides — activated via body.dark class.
   Used for Gantt (rendered with default theme for correct viewBox)
   and as reinforcement for other dark-theme diagrams. */
body.dark #diagram .section,
body.dark #diagram .section0,
body.dark #diagram .section1,
body.dark #diagram .section2,
body.dark #diagram .section3{fill:#2d2d2d !important}
body.dark #diagram .task,
body.dark #diagram .task0,
body.dark #diagram .task1,
body.dark #diagram .task2,
body.dark #diagram .task3{fill:#4a5a8a !important;stroke:#667 !important}
body.dark #diagram .taskText,
body.dark #diagram .taskText0,
body.dark #diagram .taskText1,
body.dark #diagram .taskText2,
body.dark #diagram .taskText3,
body.dark #diagram .taskTextOutsideLeft,
body.dark #diagram .taskTextOutsideRight,
body.dark #diagram .taskTextOutside0,
body.dark #diagram .taskTextOutside1,
body.dark #diagram .taskTextOutside2,
body.dark #diagram .taskTextOutside3{fill:#e0e0e0 !important}
body.dark #diagram .titleText{fill:#e0e0e0 !important}
body.dark #diagram .sectionTitle,
body.dark #diagram .sectionTitle0,
body.dark #diagram .sectionTitle1,
body.dark #diagram .sectionTitle2,
body.dark #diagram .sectionTitle3{fill:#e0e0e0 !important}
body.dark #diagram .tick text{fill:#b0b0b0 !important}
body.dark #diagram .grid .tick line{stroke:#555 !important}
body.dark #diagram .domain{stroke:#666 !important}
body.dark #diagram .today{stroke:#ff6666 !important;stroke-width:2px !important}
body.dark #diagram .done{fill:#2a5a2a !important;stroke:#696 !important}
body.dark #diagram .active{fill:#5a5a9a !important;stroke:#88a !important}
body.dark #diagram .crit{fill:#6a3a3a !important;stroke:#966 !important}
body.dark #diagram .activeCrit{fill:#6a3a3a !important;stroke:#966 !important}
body.dark #diagram .mindmap-node text{fill:#e0e0e0 !important}
body.dark #diagram .mindmap-node foreignObject span,
body.dark #diagram .mindmap-node foreignObject div{color:#e0e0e0 !important}
</style>
</head><body>
<div id="diagram"></div>
<script>

let rc=0;
function parseViewBox(svg){
  if(!svg){return {w:0,h:0,text:'none'}};
  var vb=svg.getAttribute('viewBox')||'none';
  if(vb==='none'){return {w:0,h:0,text:vb}};
  var p=vb.trim().split(/\\s+/).map(Number);
  if(p.length<4||Number.isNaN(p[2])||Number.isNaN(p[3])){
    return {w:0,h:0,text:vb};
  }
  return {w:Math.max(0,p[2]),h:Math.max(0,p[3]),text:vb};
}

function finite(v){
  return Number.isFinite(v)?v:0;
}

function measureDiagram(c){
  var s=c.querySelector('svg');
  var r=s?s.getBoundingClientRect():{width:0,height:0};
  var vb=parseViewBox(s);
  var sw=Math.ceil(finite(s?Number(s.getAttribute('width')||0):0));
  var sh=Math.ceil(finite(s?Number(s.getAttribute('height')||0):0));
  var width=Math.max(
    Math.ceil(finite(r.width||0)),
    finite(vb.w),
    sw,
    Math.ceil(finite(c.scrollWidth||0)),
    Math.ceil(finite(document.body.scrollWidth||0)),
    Math.ceil(finite(document.documentElement.scrollWidth||0))
  );
  var height=Math.max(
    Math.ceil(finite(r.height||0)),
    finite(vb.h),
    sh,
    Math.ceil(finite(c.scrollHeight||0)),
    Math.ceil(finite(document.body.scrollHeight||0)),
    Math.ceil(finite(document.documentElement.scrollHeight||0))
  );
  return {
    svg:s,
    viewBox:vb.text,
    viewBoxWidth:vb.w,
    viewBoxHeight:vb.h,
    width:width,
    height:height
  };
}

function postRendered(c,isGantt,renderTheme){
  var m=measureDiagram(c);
  window.flutter_inappwebview.callHandler('MermaidChannel',JSON.stringify({
    type:'rendered',
    width:Math.max(32,m.width+16),
    height:Math.max(32,m.height+16),
    diag:{
      isGantt:isGantt,
      renderTheme:renderTheme,
      viewBox:m.viewBox,
      w:m.width,
      h:m.height
    }
  }));
  return m;
}

async function renderMermaid(source,theme,attempt){
  attempt=attempt||0;
  const c=document.getElementById('diagram');
  const src=(source||'').trim();

  // Explicit probes rendered inside the same WebView surface used for Mermaid.
  if(src.startsWith('%%svg-probe')){
    c.innerHTML='<svg xmlns="http://www.w3.org/2000/svg" width="680" height="220" viewBox="0 0 680 220">'
      +'<defs><linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0%" stop-color="#1f2937"/><stop offset="100%" stop-color="#0b1220"/></linearGradient></defs>'
      +'<rect x="0" y="0" width="680" height="220" fill="url(#bg)"/>'
      +'<rect x="20" y="20" width="640" height="180" rx="14" ry="14" fill="#111827" stroke="#38bdf8" stroke-width="2"/>'
      +'<circle cx="70" cy="90" r="28" fill="#22c55e"/>'
      +'<circle cx="145" cy="90" r="28" fill="#f59e0b"/>'
      +'<circle cx="220" cy="90" r="28" fill="#ef4444"/>'
      +'<text x="270" y="84" fill="#e5e7eb" font-size="30" font-family="Arial, Helvetica, sans-serif" font-weight="700">In-WebView SVG Probe</text>'
      +'<text x="270" y="120" fill="#cbd5e1" font-size="18" font-family="Arial, Helvetica, sans-serif">If visible, SVG inside Mermaid WebView works.</text>'
      +'</svg>';
    await new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)));
    postRendered(c,false,'probe');
    return;
  }

  if(src.startsWith('%%html-probe')){
    c.innerHTML='<div style="padding:12px;border:2px solid #38bdf8;border-radius:10px;background:#111827;color:#e5e7eb;font-family:Arial,Helvetica,sans-serif;">'
      +'<strong>In-WebView HTML Probe</strong><br/>This block is rendered inside Mermaid WebView.'
      +'</div>';
    await new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)));
    postRendered(c,false,'probe');
    return;
  }

  const isDark=(theme==='dark');
  // Toggle body class so the <head> CSS dark overrides activate.
  document.body.className=isDark?'dark':'';
  const isGantt=source.trim().split('\\n')[0].trim().toLowerCase()==='gantt';
  // Mermaid v11 Gantt bug: first render in a fresh WebView produces
  // zero-width viewBox because mermaid reads container width before
  // layout. Workaround: do a throwaway render to warm up the container,
  // then immediately re-render for real.
  if(isGantt){
    rc++;
    try{
      mermaid.initialize({startOnLoad:false,theme:'default',securityLevel:'loose'});
      var warm=await mermaid.render('warmup'+rc,source);
      c.innerHTML=warm.svg;
    }catch(e){}
    // Allow one layout pass so the container gets real dimensions.
    await new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)));
  }
  rc++;
  const id='m'+rc;
  try{
    const renderTheme=theme||'default';
    var cfg={startOnLoad:false,theme:renderTheme,securityLevel:'loose'};
    if(isDark){
      cfg.themeVariables={
        sectionBkgColor:'#2d2d2d',altSectionBkgColor:'#363636',
        taskBkgColor:'#3a3a6a',activeTaskBkgColor:'#4a4a7a',
        doneTaskBkgColor:'#2a5a2a',critBkgColor:'#6a2a2a',
        taskTextColor:'#e0e0e0',taskTextOutsideColor:'#e0e0e0',
        taskTextDarkColor:'#e0e0e0',
        gridColor:'#444444',todayLineColor:'#ff6666',
        titleColor:'#e0e0e0',sectionTitleColor:'#e0e0e0'
      };
    }
    mermaid.initialize(cfg);
    const{svg}=await mermaid.render(id,source);
    c.innerHTML=svg;
    // Post-render dark-theme DOM fixes.
    if(isDark){
      c.querySelectorAll('.mindmap-node text, .mindmap-node foreignObject span, .mindmap-node foreignObject div').forEach(function(el){
        el.style.setProperty('color','#e0e0e0','important');
        el.style.setProperty('fill','#e0e0e0','important');
      });
      c.querySelectorAll('.taskText, .taskTextOutsideRight, .taskTextOutsideLeft, .titleText, .sectionTitle').forEach(function(el){
        el.style.setProperty('fill','#e0e0e0','important');
      });
      c.querySelectorAll('.tick text').forEach(function(el){
        el.style.setProperty('fill','#b0b0b0','important');
      });
      c.querySelectorAll('.task').forEach(function(el){
        if(!el.style.fill || el.style.fill==='none'){
          el.style.setProperty('fill','#3a3a6a','important');
        }
      });
      c.querySelectorAll('.section0,.section1,.section2,.section3').forEach(function(el){
        var cur=el.getAttribute('fill')||el.style.fill||'';
        if(!cur||cur==='#ffffff'||cur==='white'||cur==='#fff'){
          el.style.setProperty('fill','#2d2d2d','important');
        }
      });
      c.querySelectorAll('.grid .tick line').forEach(function(el){
        el.style.setProperty('stroke','#444','important');
      });
    }
    // Wait for layout, then measure with retries when dimensions are unstable.
    await new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)));
    var m=postRendered(c,isGantt,renderTheme);
    var zeroOrTiny=m.width<32||m.height<32;
    var invalidGantt=isGantt&&(m.viewBoxWidth<1||m.viewBoxHeight<1);
    if((zeroOrTiny||invalidGantt)&&attempt<3){
      await new Promise(r=>setTimeout(r,40));
      return renderMermaid(source,theme,attempt+1);
    }

    // Send one more stabilized size after the browser settles late layout.
    setTimeout(function(){postRendered(c,isGantt,renderTheme);},80);
  }catch(e){
    c.innerHTML='<div class="error">'+
      (e.message||String(e)).replace(/</g,'&lt;')+'</div>';
    window.flutter_inappwebview.callHandler('MermaidChannel',JSON.stringify({
      type:'error',
      message:e.message||String(e)
    }));
  }
}
// Forward wheel events to Flutter so the parent ScrollView can scroll.
document.addEventListener('wheel',function(e){
  e.preventDefault();
  var dy=e.deltaY;
  if(e.deltaMode===1)dy*=16;
  if(e.deltaMode===2)dy*=window.innerHeight;
  window.flutter_inappwebview.callHandler('MermaidChannel',JSON.stringify({type:'scroll',deltaX:e.deltaX,deltaY:dy}));
},{passive:false,capture:true});
</script>
</body></html>''';
  }

  @override
  Widget build(BuildContext context) {
    if (!_platformAvailable || _error != null) {
      return _buildErrorFallback();
    }

    // Mermaid.js not loaded yet — show loading.
    if (_mermaidJs == null || _initialData == null) {
      return SizedBox(
        width: double.infinity,
        height: widget.minHeight,
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final bgColor = widget.backgroundColor ?? Colors.white;

    return SizedBox(
      width: double.infinity,
      height: _height,
      child: Stack(
        children: [
          InAppWebView(
            key: _webViewKey,
            initialData: _initialData!,
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              transparentBackground: false,
              disableHorizontalScroll: true,
              disableVerticalScroll: true,
              supportZoom: false,
            ),
            onWebViewCreated: _onWebViewCreated,
            onLoadStop: _onLoadStop,
            onConsoleMessage: (controller, consoleMessage) {
              debugPrint(
                '[MermaidWebView][JS] ${consoleMessage.messageLevel}: ${consoleMessage.message}',
              );
            },
          ),

          if (_loading)
            Positioned.fill(
              child: Container(
                color: bgColor.withValues(alpha: 0.8),
                child: const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildErrorFallback() {
    final isLinux = !kIsWeb && Platform.isLinux;
    final title = isLinux
        ? 'Mermaid preview unavailable on Linux'
        : (_error != null ? 'Diagram render failed' : 'WebView unavailable');
    final subtitle = isLinux
        ? 'WebView is not supported on Linux desktop'
        : _error;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                isLinux ? Icons.desktop_windows : Icons.warning_amber_rounded,
                size: 16,
                color: isLinux ? Colors.blue.shade600 : Colors.orange.shade700,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade500,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: SelectableText(
              widget.source,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: Colors.grey.shade700,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
