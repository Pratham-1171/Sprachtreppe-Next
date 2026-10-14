/* Source module: settings-boot.js
 * Settings, theme, language, and app startup.
 * Build: scripts/build-course.py concatenates modules in its declared order.
 */
function viewSettings(el){
  const st = S.settings;
  el.innerHTML = `<h2>${t('settings_title')}</h2><p class="sub">${t('settings_sub')}</p>
    <div class="settings-section"><h4>General</h4>
      <div class="setting-row"><div><div class="sr-label">Theme</div></div>
        <select id="s-theme"><option value="light" ${st.theme==='light'?'selected':''}>Light</option><option value="dark" ${st.theme==='dark'?'selected':''}>Dark</option></select></div>
      <div class="setting-row"><div><div class="sr-label">Font size</div></div>
        <select id="s-font"><option value="small" ${st.fontSize==='small'?'selected':''}>Small</option><option value="normal" ${st.fontSize==='normal'?'selected':''}>Normal</option><option value="large" ${st.fontSize==='large'?'selected':''}>Large</option></select></div>
    </div>
    <div class="settings-section"><h4>Interface</h4>
      <div class="setting-row"><div><div class="sr-label">Compact navigation</div></div>
        <label class="switch"><input type="checkbox" id="s-compactnav" ${st.compactNav?'checked':''}><span></span></label></div>
      <div class="setting-row"><div><div class="sr-label">Reduce animations</div></div>
        <label class="switch"><input type="checkbox" id="s-reducemotion" ${st.reduceMotion?'checked':''}><span></span></label></div>
    </div>
    <div class="settings-section"><h4>Audio</h4>
      <div class="setting-row"><div><div class="sr-label">Pronunciation enabled</div></div>
        <label class="switch"><input type="checkbox" id="s-audioen" ${st.audioEnabled?'checked':''}><span></span></label></div>
      <div class="setting-row"><div><div class="sr-label">Auto-play</div></div>
        <label class="switch"><input type="checkbox" id="s-autoplay" ${st.autoPlay?'checked':''}><span></span></label></div>
      <div class="setting-row"><div><div class="sr-label">Speech rate</div></div>
        <select id="s-rate">${[0.6,0.7,0.8,0.9,1.0,1.1,1.2,1.3,1.4].map(r => `<option value="${r}" ${Math.abs(st.speechRate-r)<0.05?'selected':''}>${r}x</option>`).join('')}</select></div>
    </div>
    <div class="settings-section"><h4>Exercise</h4>
      <div class="setting-row"><div><div class="sr-label">Default questions</div></div>
        <select id="s-count">${[5,10,20,50].map(n => `<option value="${n}" ${st.defaultCount===n?'selected':''}>${n}</option>`).join('')}</select></div>
      <div class="setting-row"><div><div class="sr-label">Default difficulty</div></div>
        <select id="s-diff">${['easy','normal','hard','expert','mixed'].map(d => `<option value="${d}" ${st.defaultDifficulty===d?'selected':''}>${d}</option>`).join('')}</select></div>
    </div>
    <div class="settings-section"><h4>Learning</h4>
      <div class="setting-row"><div><div class="sr-label">Daily goal (questions)</div></div>
        <select id="s-goal">${[10,20,30,45,60].map(n => `<option value="${n}" ${st.dailyGoal===n?'selected':''}>${n}</option>`).join('')}</select></div>
    </div>
    <div class="settings-section"><h4>Data</h4>
      <div class="row"><button class="btn" id="exP">📤 Export</button>
      <label class="btn ghost" style="cursor:pointer">📥 Import<input type="file" id="imP" accept="application/json" hidden></label></div>
      <div class="row" style="margin-top:8px">
        <button class="btn ghost" id="clearM">Clear mistakes</button>
        <button class="btn ghost" id="clearS">Clear SRS</button>
        <button class="btn ghost" id="resetAll">Reset all</button>
      </div>
    </div>
    <div class="center mini-muted mt" id="saveInd" style="opacity:0;transition:opacity .3s">✓ Saved</div>`;
  const flash = () => { const i = $('#saveInd'); i.style.opacity = 1; setTimeout(() => i.style.opacity = 0, 1200); };
  const apply = () => { applySettingsToDOM(); STORE.save(); flash(); };
  $('#s-theme').onchange = e => { S.settings.theme = e.target.value; applyTheme(); apply(); };
  $('#s-font').onchange = e => { S.settings.fontSize = e.target.value; apply(); };
  $('#s-compactnav').onchange = e => { S.settings.compactNav = e.target.checked; apply(); };
  $('#s-reducemotion').onchange = e => { S.settings.reduceMotion = e.target.checked; apply(); };
  $('#s-audioen').onchange = e => { S.settings.audioEnabled = e.target.checked; apply(); };
  $('#s-autoplay').onchange = e => { S.settings.autoPlay = e.target.checked; apply(); };
  $('#s-rate').onchange = e => { S.settings.speechRate = parseFloat(e.target.value); apply(); };
  $('#s-count').onchange = e => { S.settings.defaultCount = parseInt(e.target.value, 10); apply(); };
  $('#s-diff').onchange = e => { S.settings.defaultDifficulty = e.target.value; apply(); };
  $('#s-goal').onchange = e => { S.settings.dailyGoal = parseInt(e.target.value, 10); apply(); };
  $('#exP').onclick = () => {
    const payload = {version:5.3, exportedAt:new Date().toISOString(), store:S};
    const blob = new Blob([JSON.stringify(payload, null, 2)], {type:'application/json'});
    const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = 'german-a1-b1-progress.json'; a.click();
    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
  };
  $('#imP').onchange = e => {
    const file = e.target.files[0]; if(!file) return;
    const r = new FileReader();
    r.onload = () => { try{ const p = JSON.parse(r.result); if(p.store) localStorage.setItem(STORE.key, JSON.stringify(p.store)); alert('Imported! Reloading…'); location.reload(); }catch(err){ alert('Invalid file.'); } };
    r.readAsText(file);
  };
  $('#clearM').onclick = () => { if(confirm('Clear all mistakes?')){ clearAllMistakes(); flash(); } };
  $('#clearS').onclick = () => { if(confirm('Clear all mastery data?')){ S.mastery = {}; STORE.save(); flash(); } };
  $('#resetAll').onclick = () => { if(confirm('Reset everything?')){ localStorage.removeItem(STORE.key); location.reload(); } };
}

/* ============================================================
   THEME + BOOT
   ============================================================ */
function applyTheme(){
  document.documentElement.setAttribute('data-theme', S.settings.theme || 'light');
  $('#themeBtn').textContent = (S.settings.theme === 'dark') ? '☀️' : '🌙';
}
function applySettingsToDOM(){
  document.documentElement.setAttribute('data-fontsize', S.settings.fontSize || 'normal');
  document.documentElement.setAttribute('data-compactnav', S.settings.compactNav ? '1' : '0');
  document.documentElement.setAttribute('data-reducemotion', S.settings.reduceMotion ? '1' : '0');
}
function applyLanguage(renderView){
  const changed = S.settings.lang !== 'en' || Object.prototype.hasOwnProperty.call(S.settings, 'translationMode');
  S.settings.lang = 'en';
  delete S.settings.translationMode;
  document.documentElement.lang = 'en';
  buildNav();
  if(changed) STORE.save();
  if(renderView) route();
}

$('#themeBtn').onclick = e => { e.preventDefault(); e.stopPropagation(); S.settings.theme = (S.settings.theme === 'dark') ? 'light' : 'dark'; STORE.save(); applyTheme(); };
$('#settingsBtn').onclick = e => {
  e.preventDefault();
  e.stopPropagation();
  /* Staff dashboards use their own hash routes. Do NOT change the hash here:
     another LMS/auth route refresh can immediately overwrite #/settings. Render
     the settings view directly and leave the staff dashboard route untouched. */
  if (window.SP_LMS && window.SP_LMS.isStaff && window.SP_LMS.isStaff()) {
    if (typeof viewSettings === 'function') viewSettings($('#view'));
    return false;
  }
  location.hash = '#/settings';
};

buildNav();
applyTheme();
applySettingsToDOM();
applyLanguage(false);
route();