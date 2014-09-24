// Copyright (c) 2013, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

library cde_polymer_designer;

import 'dart:async';
import 'dart:js' as js;

import 'package:chrome/chrome_app.dart' as chrome;
import 'package:polymer/polymer.dart';

@CustomTag('cde-polymer-designer')
class CdePolymerDesigner extends PolymerElement {
  js.JsObject _webview;
  Completer _webviewReady = new Completer();
  Completer<String> _code;

  CdePolymerDesigner.created() : super.created();

  @override
  void attached() {
    super.attached();

    _webview = new js.JsObject.fromBrowserObject($['webview']);
    _webview.callMethod('addEventListener', ['contentload', _onContentLoad]);
  }

  Future reload() {
    final completer = new Completer();
    _webview.callMethod('reload', [(_) => completer.complete()]);
    return completer.future;
  }

  Future<String> getCode() {
    _webviewReady.future.then((_) {
      _code = new Completer<String>();
      _executeScriptInWebview('''
          window.postMessage({action: 'get_code'}, '*');
      ''');
    });
    return _code.future;
  }

  Future setCode(String code) {
    code = code.replaceAll('"', r'\"').replaceAll('\n', r'\n');
    return _webviewReady.future.then((_) {
      return new Timer(new Duration(milliseconds: 500), () {
        return _executeScriptInWebview('''
            window.postMessage({action: 'set_code', args: '$code'}, '*');
        ''');
      });
    });
  }

  void _onContentLoad(_) {
    _tweakUI();
    _registerWebviewProxyListener();
    _injectWebviewProxy().then((_) => _webviewReady.complete());
  }

  Future _tweakUI() {
    _insertCssIntoWebview(r'''
        #designer::shadow > #appbar > * { display: none; } 
        #designer::shadow > #appbar > .design-controls { display: block; }
    ''');
  }

  void _registerWebviewProxyListener() {
    chrome.runtime.onMessage.listen((OnMessageEvent event) {
      // TODO(ussuri): Check the sender.
      if (event.message['type'] == 'code') {
        _code.complete("${event.message['value']}");
      }
    });
  }

  Future _injectWebviewProxy() {
    // TODO(ussuri): Check the sender.
    return _injectWebviewScriptingContextScript(r'''
        window.addEventListener("message", function(event) {
          var designer = document.querySelector("#designer");
          if (event.data['action'] === 'get_code') {
            chrome.runtime.sendMessage({type: 'code', value: designer.html});
          } else if (event.data['action'] === 'set_code') {
            designer.loadHtml(event.data['args']);
          }
        });
    ''');
  }

  Future _injectWebviewScriptingContextScript(String script) {
    script = script.replaceAll('"', r'\"').replaceAll('\n', r'\n');
    return _executeScriptInWebview(r'''
        (function() {
          var script = document.createElement("script");
          script.innerHTML = "(function() { ''' + script + r'''; })()";
          document.body.appendChild(script);
        })();
    ''');
  }

  Future<dynamic> _executeScriptInWebview(String script) {
    script = new js.JsObject.jsify({'code': script});
    final completer = new Completer();
    _webview.callMethod('executeScript', 
        [script, (result) => completer.complete(result)]);
    return completer.future;
  }

  void _insertCssIntoWebview(String css) {
    css = new js.JsObject.jsify({'code': css});
    _webview.callMethod('insertCSS', [css, (_) {}]);
  }
}
