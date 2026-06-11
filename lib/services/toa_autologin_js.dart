import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Autologin SSO TOA / Microsoft Entra (Mis Actividades).
class ToaAutologinJs {
  /// Inyecta (o reinyecta) el script con credenciales frescas.
  /// Seguro llamarlo en cada tick — así funcionaba el flujo original.
  static Future<void> inject(
    WebViewController controller,
    Map<String, String> creds, {
    bool forcePicker = false,
  }) async {
    final userLit = jsonEncode(creds['usuario'] ?? '');
    final emailLit = jsonEncode(creds['email'] ?? creds['usuario'] ?? '');
    final passLit = jsonEncode(creds['pass'] ?? '');
    final forcePickerLit = forcePicker ? 'true' : 'false';

    final js = '''
(function() {
  var USUARIO = $userLit;
  var EMAIL = $emailLit;
  var PASS = $passLit;
  var FORCE_PICKER = $forcePickerLit;

$_scriptBody
})();
''';
    try {
      await controller.runJavaScript(js);
    } catch (e, st) {
      debugPrint('[TOA Autologin] runJavaScript error: $e\n$st');
    }
  }

  /// Dispara clic en "Usar otra cuenta" (salta el tile del picker).
  static Future<void> useAnotherAccount(WebViewController controller) async {
    try {
      await controller.runJavaScript(
        'try { if (window.__creaboxUseAnotherAccount) window.__creaboxUseAnotherAccount(); } catch(_) {}',
      );
    } catch (e) {
      debugPrint('[TOA Autologin] useAnotherAccount error: $e');
    }
  }

  /// @deprecated Usar [useAnotherAccount] + recuperación por cookies.
  static Future<void> pulsePickerClick(WebViewController controller) async {
    await useAnotherAccount(controller);
  }

  static const _scriptBody = r'''
  function log(msg) { /* logs desactivados */ }
  function postStage(s) {
    if (window.__creabox_last_stage === s) return;
    window.__creabox_last_stage = s;
    try { creaboxStage.postMessage(s); } catch(_) {}
  }

  function visible(el) {
    if (!el) return false;
    try {
      var st = window.getComputedStyle(el);
      if (st.display === 'none' || st.visibility === 'hidden') return false;
      if (parseFloat(st.opacity || '1') < 0.05) return false;
      var r = el.getBoundingClientRect();
      if (r.width > 2 && r.height > 2) return true;
      return el.offsetParent !== null;
    } catch(_) {
      return el.offsetParent !== null;
    }
  }

  function safeClick(el) {
    if (!el) return false;
    try {
      el.focus();
      var r = el.getBoundingClientRect();
      var cx = r.left + r.width / 2;
      var cy = r.top + r.height / 2;
      ['pointerdown', 'mousedown', 'pointerup', 'mouseup', 'click'].forEach(function(type) {
        el.dispatchEvent(new MouseEvent(type, {
          bubbles: true, cancelable: true, view: window,
          clientX: cx, clientY: cy
        }));
      });
      if (typeof el.click === 'function') el.click();
      return true;
    } catch(_) { return false; }
  }

  function runOnAllDocs(fn) {
    fn(document);
    var iframes = document.querySelectorAll('iframe');
    for (var i = 0; i < iframes.length; i++) {
      try {
        var d = iframes[i].contentDocument;
        if (d) fn(d);
      } catch(_) {}
    }
  }

  function isOfscHost(host) {
    host = (host || '').toLowerCase();
    return host.indexOf('etadirect.com') >= 0 ||
      host.indexOf('oraclecloud.com') >= 0 ||
      host.indexOf('oracle.com') >= 0;
  }

  function pageText(doc) {
    return ((doc.body && doc.body.innerText) || '').toLowerCase();
  }

  function isOfscLoginDoc(doc) {
    var txt = pageText(doc);
    return txt.indexOf('oracle field service') >= 0 ||
      txt.indexOf('conectarse con sso') >= 0 ||
      txt.indexOf('sign in with sso') >= 0 ||
      txt.indexOf('nombre de usuario') >= 0 ||
      txt.indexOf('iniciar sesión') >= 0 ||
      !!doc.getElementById('sign-in-with-sso') ||
      !!doc.getElementById('sso_username') ||
      !!doc.getElementById('organization') ||
      !!doc.querySelector('input[type="password"]');
  }

  function findSsoButton(doc) {
    var byId = doc.getElementById('sign-in-with-sso');
    if (byId && visible(byId)) return byId;

    var byClass = doc.querySelector('.sign-in-with-sso, a.sign-in-with-sso, button.sign-in-with-sso');
    if (byClass && visible(byClass)) return byClass;

    var candidates = doc.querySelectorAll(
      'button, a, input[type="button"], input[type="submit"], div[role="button"], span[role="button"]'
    );
    for (var i = 0; i < candidates.length; i++) {
      var b = candidates[i];
      if (!visible(b)) continue;
      var t = ((b.textContent || b.value || b.getAttribute('aria-label')) || '').toLowerCase();
      if (t.indexOf('conectarse con sso') >= 0 ||
          t.indexOf('sign in with sso') >= 0 ||
          t.indexOf('connect with sso') >= 0 ||
          (t.indexOf('sso') >= 0 && t.indexOf('conect') >= 0)) {
        return b;
      }
    }
    return null;
  }

  function isMicrosoftSignedOut(doc) {
    var txt = pageText(doc);
    return txt.indexOf('cerró la sesión') >= 0 ||
      txt.indexOf('cerro la sesion') >= 0 ||
      txt.indexOf('signed out of your account') >= 0 ||
      txt.indexOf('signed out') >= 0 && txt.indexOf('account') >= 0 ||
      txt.indexOf('cierre todas las ventanas') >= 0 ||
      txt.indexOf('close all browser') >= 0;
  }

  function detectStage() {
    var host = location.hostname.toLowerCase();
    if (isOfscHost(host)) {
      var loginVisible = !!(
        document.getElementById('sign-in-with-sso') ||
        document.getElementById('sso_username') ||
        document.getElementById('organization') ||
        document.getElementById('continue-with-sso') ||
        findSsoButton(document)
      );
      if (!loginVisible) {
        runOnAllDocs(function(doc) {
          if (loginVisible) return;
          if (isOfscLoginDoc(doc)) loginVisible = true;
        });
      }
      return loginVisible ? 'loading' : 'done';
    }
    if (host.indexOf('login.microsoftonline.com') >= 0 ||
        host.indexOf('login.live.com') >= 0 ||
        host.indexOf('login.microsoft.com') >= 0) {
      var bodyTxt = (document.body.innerText || '').toLowerCase();
      if (bodyTxt.indexOf('aadsts') >= 0) return 'error_aad';
      if (isMicrosoftSignedOut(document)) return 'signed_out';
      var pickerVisible = isAccountPickerDoc(document);
      if (!pickerVisible) {
        runOnAllDocs(function(doc) {
          if (!pickerVisible && isAccountPickerDoc(doc)) pickerVisible = true;
        });
      }
      if (pickerVisible) return 'picker';
      var emailEl = document.querySelector('input[name="loginfmt"], input#i0116');
      if (emailEl && visible(emailEl)) return 'loading';
      var hasMfaText =
        bodyTxt.indexOf('aprobar') >= 0 ||
        bodyTxt.indexOf('aprueba') >= 0 ||
        bodyTxt.indexOf('verifica tu identidad') >= 0 ||
        bodyTxt.indexOf('approve sign-in') >= 0 ||
        bodyTxt.indexOf('verify your identity') >= 0 ||
        bodyTxt.indexOf('authenticator') >= 0;
      if (hasMfaText || !!document.querySelector('input[name="otc"]')) return 'mfa';
      if (bodyTxt.indexOf('mantener la sesi') >= 0 || bodyTxt.indexOf('stay signed in') >= 0) return 'kmsi';
      return 'loading';
    }
    return 'done';
  }

  function setVal(el, v) {
    var s = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
    s.call(el, v);
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
    el.dispatchEvent(new Event('keyup', { bubbles: true }));
  }

  function isAccountPickerDoc(doc) {
    var bodyTxt = ((doc.body && doc.body.innerText) || '').toLowerCase();
    return (bodyTxt.indexOf('selecci') >= 0 && bodyTxt.indexOf('cuenta') >= 0) ||
      bodyTxt.indexOf('pick an account') >= 0 ||
      bodyTxt.indexOf('choose an account') >= 0 ||
      !!doc.getElementById('tilesHolder') ||
      !!doc.querySelector('[data-test-id^="accountTile"]');
  }

  function findClickableAncestor(el, doc) {
    var cur = el;
    for (var i = 0; i < 14 && cur && cur !== doc.body; i++) {
      var tag = (cur.tagName || '').toLowerCase();
      var role = cur.getAttribute && cur.getAttribute('role');
      var cls = (cur.className || '').toString().toLowerCase();
      if (tag === 'button' || tag === 'a' || role === 'button' || role === 'option' ||
          role === 'listitem' || cls.indexOf('table-row') >= 0 ||
          cls.indexOf('tile') >= 0 ||
          cur.getAttribute('tabindex') === '0') {
        return cur;
      }
      cur = cur.parentElement;
    }
    return el;
  }

  function findTableRow(el) {
    var cur = el;
    for (var i = 0; i < 8 && cur; i++) {
      var cls = (cur.className || '').toString().toLowerCase();
      if (cls.indexOf('table-row') >= 0) return cur;
      cur = cur.parentElement;
    }
    return el;
  }

  function pressEnter(el) {
    if (!el) return;
    try {
      ['keydown', 'keypress', 'keyup'].forEach(function(type) {
        el.dispatchEvent(new KeyboardEvent(type, {
          bubbles: true, cancelable: true, key: 'Enter', code: 'Enter',
          keyCode: 13, which: 13
        }));
      });
    } catch(_) {}
  }

  function tryPickerClick(doc, el, label) {
    if (!el || !visible(el)) return false;
    // Preferir el tile con data-test-id (el que tiene el handler real).
    var tile = null;
    try {
      tile = (el.matches && el.matches('[data-test-id^="accountTile"]')) ? el :
        (el.querySelector && el.querySelector('[data-test-id^="accountTile"]')) ||
        el.closest('[data-test-id^="accountTile"]');
    } catch(_) {}
    var targets = [];
    if (tile) targets.push(tile);
    targets.push(findTableRow(el));
    targets.push(el);
    for (var ti = 0; ti < targets.length; ti++) {
      var t = targets[ti];
      if (!t || !visible(t)) continue;
      try { t.focus(); } catch(_) {}
      safeClick(t);
      pressEnter(t);
      try { if (typeof t.click === 'function') t.click(); } catch(_) {}
      window.__creabox_picker_click_at = Date.now();
      window.__creabox_picker_tries = (window.__creabox_picker_tries || 0) + 1;
      log('entra: click ' + label + ' (#' + window.__creabox_picker_tries + ')');
      return true;
    }
    return false;
  }

  function clickOtraCuenta(doc) {
    var sels = [
      '#otherTile', '[data-test-id="otherTile"]', '#otherTileText',
      '.use-another-account', '[data-test-id="other"]'
    ];
    for (var i = 0; i < sels.length; i++) {
      var o = doc.querySelector(sels[i]);
      if (o && visible(o)) {
        try { o.focus(); } catch(_) {}
        safeClick(o);
        pressEnter(o);
        try { if (typeof o.click === 'function') o.click(); } catch(_) {}
        window.__creabox_picker_click_at = Date.now();
        log('entra: click otra cuenta (selector)');
        return true;
      }
    }
    var btns = doc.querySelectorAll('.table-row, div[role="button"], button, a, li');
    for (var m = 0; m < btns.length; m++) {
      var b = btns[m];
      if (!visible(b)) continue;
      var t = ((b.textContent || b.innerText) || '').toLowerCase();
      if (t.indexOf('otra cuenta') >= 0 || t.indexOf('another account') >= 0 ||
          t.indexOf('use another') >= 0 || t.indexOf('usar otra') >= 0) {
        try { b.focus(); } catch(_) {}
        safeClick(b);
        pressEnter(b);
        try { if (typeof b.click === 'function') b.click(); } catch(_) {}
        window.__creabox_picker_click_at = Date.now();
        log('entra: click otra cuenta (texto)');
        return true;
      }
    }
    return false;
  }

  function processAccountPickerInDoc(doc) {
    if (!isAccountPickerDoc(doc)) return false;

    // Si ya hay campo email, dejar que processEntra lo maneje.
    var emailEl = doc.querySelector('input[name="loginfmt"], input#i0116');
    if (emailEl && visible(emailEl)) return false;

    var now = Date.now();
    if (window.__creabox_picker_click_at && now - window.__creabox_picker_click_at < 1200) {
      return false;
    }

    log('entra: picker → ir a formulario email');
    return clickOtraCuenta(doc);
  }

  function processAccountPicker() {
    var clicked = false;
    runOnAllDocs(function(doc) {
      if (!clicked && processAccountPickerInDoc(doc)) clicked = true;
    });
    return clicked;
  }

  function processEtadirectInDoc(doc) {
    var step2 = doc.getElementById('second-step-container-sso');
    var ssoUser = doc.getElementById('sso_username');
    var continueBtn = doc.getElementById('continue-with-sso');
    var orgEl = doc.getElementById('organization');
    var ssoBtn = doc.getElementById('sign-in-with-sso') || findSsoButton(doc);

    // Paso 2 SSO: solo cuando el contenedor del paso está visible (como el flujo original).
    if (visible(step2) && ssoUser) {
      if (ssoUser.value !== USUARIO) {
        setVal(ssoUser, USUARIO);
        log('etadirect: rellené sso_username');
        setTimeout(function() {
          var b = doc.getElementById('continue-with-sso');
          if (b && !b.disabled && visible(b)) {
            safeClick(b);
            log('etadirect: click Continuar');
          }
        }, 500);
      } else if (continueBtn && !continueBtn.disabled && visible(continueBtn)) {
        safeClick(continueBtn);
        log('etadirect: click Continuar (ya lleno)');
      }
      return;
    }

    if (visible(orgEl) && orgEl.value !== USUARIO) {
      setVal(orgEl, USUARIO);
      log('etadirect: rellené organization');
      setTimeout(function() {
        var b = doc.getElementById('continue-with-sso') ||
                doc.querySelector('button[type="submit"], input[type="submit"]');
        if (b && visible(b) && !b.disabled) {
          safeClick(b);
          log('etadirect: click Continuar (org)');
        }
      }, 500);
      return;
    }

    // Landing Oracle: pulsar "Conectarse con SSO".
    if (ssoBtn && visible(ssoBtn) && !ssoBtn.disabled) {
      if (safeClick(ssoBtn)) {
        log('etadirect: click Conectarse con SSO');
      } else {
        try { ssoBtn.click(); log('etadirect: click SSO (fallback .click)'); } catch(_) {}
      }
      return;
    }

    if (isOfscLoginDoc(doc)) {
      log('etadirect: login visible, SSO no encontrado');
    }
  }

  function processEntraInDoc(doc) {
    if (isAccountPickerDoc(doc)) return;

    var emailEl = doc.querySelector('input[name="loginfmt"], input#i0116');
    var passEl = doc.querySelector('input[name="passwd"], input#i0118');
    var siBtn = doc.querySelector('input#idSIButton9, button#idSIButton9');
    var bodyTxt = ((doc.body && doc.body.innerText) || '').toLowerCase();

    if (visible(emailEl) && (!emailEl.value || emailEl.value !== EMAIL)) {
      setVal(emailEl, EMAIL);
      log('entra: rellené email');
      setTimeout(function() {
        var b = doc.querySelector('input#idSIButton9, button#idSIButton9');
        if (b && visible(b) && !b.disabled) { safeClick(b); log('entra: click Siguiente (email)'); }
      }, 600);
      return;
    }
    if (visible(passEl) && !passEl.value) {
      setVal(passEl, PASS);
      log('entra: rellené password');
      setTimeout(function() {
        var b = doc.querySelector('input#idSIButton9, button#idSIButton9');
        if (b && visible(b) && !b.disabled) { safeClick(b); log('entra: click Iniciar sesión'); }
      }, 600);
      return;
    }
    var inKmsi = (bodyTxt.indexOf('sesi') >= 0 && bodyTxt.indexOf('iniciada') >= 0) ||
                 bodyTxt.indexOf('stay signed in') >= 0;
    if (inKmsi && siBtn && visible(siBtn)) {
      var kmsi = doc.querySelector('#KmsiCheckboxField, input[name="DontShowAgain"]');
      if (kmsi && !kmsi.checked) {
        try { kmsi.click(); log('entra: marqué "no volver a preguntar"'); } catch(_) {}
      }
      setTimeout(function() {
        var b = doc.querySelector('input#idSIButton9, button#idSIButton9');
        if (b && visible(b) && !b.disabled) { safeClick(b); log('entra: click Sí (mantener sesión)'); }
      }, 400);
    }
  }

  function process() {
    var stage = detectStage();
    postStage(stage);
    if (stage === 'signed_out' || stage === 'done') return;
    var host = location.hostname.toLowerCase();
    if (isOfscHost(host)) {
      var now = Date.now();
      if (!window.__creabox_tick_log_at || now - window.__creabox_tick_log_at > 4000) {
        window.__creabox_tick_log_at = now;
        log('tick etadirect ' + host);
      }
      runOnAllDocs(processEtadirectInDoc);
    } else if (host.indexOf('login.microsoftonline.com') >= 0 ||
               host.indexOf('login.live.com') >= 0 ||
               host.indexOf('login.microsoft.com') >= 0) {
      if (processAccountPicker()) return;
      runOnAllDocs(processEntraInDoc);
    }
  }

  if (window.__creabox_obs) {
    try { window.__creabox_obs.disconnect(); } catch(_) {}
    window.__creabox_obs = null;
  }

  process();

  var obs = new MutationObserver(function() { process(); });
  try {
    if (document.body) {
      obs.observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ['style', 'class', 'disabled'] });
      window.__creabox_obs = obs;
    }
  } catch(_) {}

  window.__creaboxClickPicker = function(force) {
    window.__creaboxForcePicker = !!force;
    return processAccountPicker();
  };

  window.__creaboxUseAnotherAccount = function() {
    var clicked = false;
    runOnAllDocs(function(doc) {
      if (!clicked && clickOtraCuenta(doc)) clicked = true;
    });
    return clicked;
  };
''';
}
