/* Renders the questions index from data/*.json.
   Nothing is baked into QUESTIONS.html, so regenerating the data is enough.

   Build is lazy: on load only the active project's cards are built; each
   project's section is built when its tab is first shown, and the heavy
   SQL/result and schema panels are built the first time they are opened.
   Every path (tab, card jump, summary click, expand-all, print) funnels
   through the same idempotent builders below. */
(function () {
  'use strict';

  var KEYWORDS = new Set(('SELECT FROM WHERE GROUP BY ORDER HAVING LIMIT OFFSET AS ON AND OR NOT IN IS ' +
    'NULL CASE WHEN THEN ELSE END JOIN LEFT RIGHT INNER OUTER CROSS FULL UNION ALL WITH DISTINCT OVER ' +
    'PARTITION ROWS RANGE BETWEEN PRECEDING FOLLOWING CURRENT ROW UNBOUNDED DESC ASC VALUES CAST LIKE ' +
    'EXISTS INTEGER REAL TEXT NULLS LAST FIRST USING').split(' '));
  var FUNCS = new Set(('COUNT SUM AVG MIN MAX ROUND ABS SQRT POWER LOG COALESCE NULLIF LENGTH REPLACE ' +
    'TRIM SUBSTR STRFTIME JULIANDAY DATE LOWER UPPER RANK DENSE_RANK ROW_NUMBER NTILE LAG LEAD ' +
    'PERCENT_RANK FIRST_VALUE GROUP_CONCAT IFNULL').split(' '));

  function esc(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;')
                    .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  /* Comments and strings are matched first, so a keyword inside either is never recoloured. */
  function highlight(sql) {
    var re = /(--[^\n]*)|('(?:''|[^'])*')|(\b\d+\.?\d*\b)|(\b[A-Za-z_][A-Za-z_0-9]*\b)/g;
    var out = '', pos = 0, first = true, m;
    while ((m = re.exec(sql)) !== null) {
      out += esc(sql.slice(pos, m.index));
      if (m[1] !== undefined) {
        var cls = (first && /^--\s*Q\d+\s*:/.test(m[1])) ? 'c q1' : 'c';
        first = false;
        out += '<span class="' + cls + '">' + esc(m[1]) + '</span>';
      } else if (m[2] !== undefined) { out += '<span class="s">' + esc(m[2]) + '</span>'; }
      else if (m[3] !== undefined) { out += '<span class="n">' + esc(m[3]) + '</span>'; }
      else {
        var u = m[4].toUpperCase();
        if (KEYWORDS.has(u))    out += '<span class="k">' + esc(m[4]) + '</span>';
        else if (FUNCS.has(u))  out += '<span class="f">' + esc(m[4]) + '</span>';
        else                    out += esc(m[4]);
      }
      pos = m.index + m[0].length;
    }
    return out + esc(sql.slice(pos));
  }

  var nf = new Intl.NumberFormat('en-US');
  function plural(n, w) { return nf.format(n) + ' ' + w + (n === 1 ? '' : 's'); }

  function render(meta, schema, results) {
    var base = 'https://github.com/' + meta.repo + '/blob/' + meta.branch + '/queries/';
    var projById = {};
    meta.projects.forEach(function (p) { projById[p.id] = p; });

    /* ---------- markup builders (pure strings) ---------- */

    function cardHtml(p, q) {
      var r = (results[p.file] || {})[q.n] || {};
      var foot = r.n === undefined ? '' : plural(r.n, 'row') + ' · ' + Math.round(r.ms) + ' ms';
      return '<a class="card" href="#p' + p.id + 'q' + q.n + '">' +
        '<span class="qn">Q' + q.n + '</span><p class="q">' + esc(q.q) + '</p>' +
        '<span class="file">' + foot + '<span class="go">view SQL &rarr;</span></span></a>';
    }

    function rqHtml(p, q) {
      var r = (results[p.file] || {})[q.n] || {};
      var head = '', rows = '';
      (r.cols || []).forEach(function (c) { head += '<th scope="col">' + esc(c) + '</th>'; });
      (r.rows || []).forEach(function (row) {
        rows += '<tr>';
        row.forEach(function (v) { rows += '<td>' + esc(v) + '</td>'; });
        rows += '</tr>';
      });
      var more = (r.n > (r.rows || []).length) ? ' · showing first ' + (r.rows || []).length : '';
      return '<div class="rq" id="p' + p.id + 'q' + q.n + '">' +
        '<h4>Q' + q.n + ' <span class="rmeta">' + esc(q.q) + '</span></h4>' +
        '<div class="rsrc"><span>' + plural(r.n || 0, 'row') + ' · ' +
          (r.cols || []).length + ' cols · ' + Math.round(r.ms || 0) + ' ms' + more + '</span>' +
        '<a class="srclink" href="' + base + p.file + '#L' + q.line +
          '" target="_blank" rel="noopener">' + esc(p.file) + ':' + q.line +
          ' on GitHub &nearr;</a></div>' +
        '<div class="rqbody"><pre class="sql scroll" tabindex="0" aria-label="Q' + q.n + ' SQL">' +
          highlight(r.sql || '') + '</pre>' +
        '<div class="tblwrap scroll" tabindex="0" aria-label="Q' + q.n + ' result rows">' +
          '<table class="res"><thead><tr>' + head + '</tr></thead>' +
        '<tbody>' + rows + '</tbody></table></div></div></div>';
    }

    function sqlBodyHtml(p, lv) {
      var s = '';
      lv.queries.forEach(function (q) { s += rqHtml(p, q); });
      return s;
    }

    function schemaNames(tables) {
      return Object.keys(tables).sort(function (a, b) {
        var ar = a.indexOf('raw_') === 0, br = b.indexOf('raw_') === 0;
        return ar !== br ? (ar ? 1 : -1) : tables[b].rows - tables[a].rows;
      });
    }

    function schemaCounts(tables) {
      var names = schemaNames(tables), ncols = 0, npk = 0, nfk = 0;
      names.forEach(function (t) {
        var tb = tables[t];
        ncols += tb.cols.length;
        tb.cols.forEach(function (c) { if (c.pk) npk++; if (c.fk) nfk++; });
      });
      return { n: names.length, ncols: ncols, npk: npk, nfk: nfk };
    }

    function schemaBodyHtml(tables) {
      var names = schemaNames(tables), cards = '';
      names.forEach(function (t) {
        var tb = tables[t], rowsHtml = '';
        tb.cols.forEach(function (c) {
          /* a column can be both: the child side of a one-to-one is its own primary
             key AND a foreign key back to the parent. Show both badges. */
          var cls = 'col', badge = '', ref = '';
          if (c.pk) { cls += ' pk'; badge += '<span class="badge">PK</span>'; }
          if (c.fk) {
            cls += ' fk'; badge += '<span class="badge">FK</span>';
            ref = '<span class="ref">&rarr; ' + esc(c.fk[0]) + '.' + esc(c.fk[1]) + '</span>';
          }
          if (!c.pk && !c.fk && c.uq) { cls += ' uq'; badge = '<span class="badge">UQ</span>'; }
          rowsHtml += '<div class="' + cls + '"><span class="cname">' + esc(c.name) + '</span>' +
                      '<span class="ctype">' + esc(c.type || '?') + '</span>' + ref + badge + '</div>';
        });
        // a long field list is split so the card stays a sensible height:
        // over 10 fields -> 2 columns, over 20 -> 3
        var n = tb.cols.length, split = n > 20 ? 3 : n > 10 ? 2 : 1;
        cards += '<div class="tcard' + (tb.raw ? ' raw' : '') + ' split' + split + '"><div class="thead">' +
                 esc(t) + '<small>' + nf.format(tb.rows) + ' rows · ' + n + ' cols' +
                 (tb.raw ? ' · source' : '') + '</small></div>' +
                 '<div class="cols">' + rowsHtml + '</div></div>';
      });
      var legend = '<div class="legend">' +
        '<span class="chipdemo" style="background:var(--pk);color:var(--on-key)">PK</span> primary key' +
        '<span class="chipdemo" style="background:var(--fk);color:var(--on-relation)">FK</span> foreign key' +
        '<span class="chipdemo" style="background:var(--cj);color:var(--on-accent)">UQ</span> unique index' +
        '<span style="opacity:.7">faded = untouched source table</span></div>';
      return legend + '<div class="tables">' + cards + '</div>';
    }

    /* full inner HTML for one project section: header + schema shell + per-level
       (header, cards, empty SQL panel shell). Heavy bodies stay empty until opened. */
    function sectionHtml(p) {
      var cnt = schemaCounts(schema[p.id] || {});
      var body = '';
      p.levels.forEach(function (lv, li) {
        var cards = '';
        lv.queries.forEach(function (q) { cards += cardHtml(p, q); });
        body += '<div class="lvlhead lvl-' + lv.name.toLowerCase() + '"><h3>' + lv.name +
          '<span class="count">' + lv.queries.length + ' queries</span></h3><div class="skills">' +
          lv.skills.map(function (s) { return '<span class="chip">' + esc(s) + '</span>'; }).join('') +
          '</div></div><div class="grid cols' + lv.cols + '">' + cards + '</div>' +
          '<details class="panel sqlpanel" data-pid="' + p.id + '" data-lvl="' + li + '">' +
          '<summary>SQL &amp; results for all ' + lv.queries.length +
          ' queries above <span class="hint">(expand)</span></summary>' +
          '<div class="panelbody"></div></details>';
      });
      return '<header class="phead"><div class="pnum">' + p.id + '</div><div><h2>' + esc(p.title) +
        '</h2><p class="meta"><code>' + esc(p.db) + '</code> · ' + esc(p.size) +
        ' · <span class="kag">Kaggle: ' + esc(p.kaggle) + '</span></p></div></header>' +
        '<details class="panel schemapanel" data-schema="' + p.id + '"><summary>Database schema — ' +
        cnt.n + ' tables, ' + cnt.ncols + ' columns, ' + cnt.npk + ' primary / ' + cnt.nfk +
        ' foreign keys <span class="hint">(expand)</span></summary>' +
        '<div class="panelbody"></div></details>' + body;
    }

    /* ---------- lazy builders (idempotent, guarded by data-built) ---------- */

    function buildSection(sec) {
      if (sec.getAttribute('data-built')) return;
      sec.innerHTML = sectionHtml(projById[+sec.getAttribute('data-pid')]);
      sec.setAttribute('data-built', '1');
    }

    function buildPanel(d) {
      if (d.getAttribute('data-built')) return;
      var slot = d.querySelector('.panelbody');
      if (!slot) return;
      if (d.classList.contains('schemapanel')) {
        slot.innerHTML = schemaBodyHtml(schema[+d.getAttribute('data-schema')] || {});
      } else {
        var p = projById[+d.getAttribute('data-pid')];
        slot.innerHTML = sqlBodyHtml(p, p.levels[+d.getAttribute('data-lvl')]);
      }
      d.setAttribute('data-built', '1');
    }

    /* ---------- header totals + empty section shells ---------- */

    document.getElementById('totals').innerHTML =
      '<div>' + meta.totals.questions + '<span>questions</span></div>' +
      '<div>' + meta.totals.projects + '<span>projects</span></div>' +
      '<div>' + meta.totals.levels + '<span>difficulty levels</span></div>' +
      '<div>' + meta.totals.rows + '<span>source rows</span></div>';

    var tabsHtml = '', stageHtml = '';
    meta.projects.forEach(function (p, i) {
      tabsHtml += '<button role="tab" class="tab" id="tab' + p.id + '" aria-controls="p' + p.id +
        '" aria-selected="' + (i === 0) + '" tabindex="' + (i === 0 ? 0 : -1) + '">' +
        '<span class="tnum">' + p.id + '</span><span class="tname">' + esc(p.short) +
        '</span><span class="tcount">' + p.count + '</span></button>';
      stageHtml += '<section class="project" id="p' + p.id + '" data-pid="' + p.id +
        '" role="tabpanel" aria-labelledby="tab' + p.id + '" hidden></section>';
    });
    document.getElementById('tabs').innerHTML = tabsHtml;
    var stage = document.getElementById('stage');
    stage.innerHTML = stageHtml;

    /* ---------- wiring ---------- */

    var tabs = [].slice.call(document.querySelectorAll('.tab'));
    var sections = tabs.map(function (t) { return document.getElementById(t.getAttribute('aria-controls')); });
    var current = 0;

    function show(i, focus) {
      current = i;
      tabs.forEach(function (t, j) {
        var on = i === j;
        t.setAttribute('aria-selected', on ? 'true' : 'false');
        t.tabIndex = on ? 0 : -1;
      });
      buildSection(sections[i]);
      sections.forEach(function (s, j) { s.hidden = j !== i; });
      if (focus) tabs[i].focus();
      history.replaceState(null, '', '#p' + (i + 1));
    }

    function pidIndex(pid) {
      for (var k = 0; k < sections.length; k++) { if (sections[k].id === 'p' + pid) return k; }
      return -1;
    }

    // jump to a query: activate its tab, build + open the panel holding it, scroll and flash
    function openQuery(id) {
      var m = /^p(\d+)q\d+$/.exec(id);
      if (!m) return;
      var idx = pidIndex(m[1]);
      if (idx < 0) return;
      show(idx, false);
      var card = sections[idx].querySelector('a.card[href="#' + id + '"]');
      var panel = card ? card.closest('.grid').nextElementSibling : null;
      if (panel) { buildPanel(panel); panel.open = true; }
      var el = document.getElementById(id);
      if (!el) return;
      el.scrollIntoView({ behavior: 'smooth', block: 'start' });
      history.replaceState(null, '', '#' + id);
      el.classList.remove('flash'); void el.offsetWidth; el.classList.add('flash');
    }

    tabs.forEach(function (t, i) {
      t.addEventListener('click', function () { show(i, false); });
      t.addEventListener('keydown', function (e) {
        var n = null;
        if (e.key === 'ArrowRight') n = (i + 1) % tabs.length;
        else if (e.key === 'ArrowLeft') n = (i - 1 + tabs.length) % tabs.length;
        else if (e.key === 'Home') n = 0;
        else if (e.key === 'End') n = tabs.length - 1;
        if (n !== null) { e.preventDefault(); show(n, true); }
      });
    });

    /* One delegated click handler on the stage: a card jumps to its query; a
       summary click (mouse or keyboard Enter/Space) builds that panel's body
       before the native <details> toggle reveals it. */
    stage.addEventListener('click', function (e) {
      var t = e.target;
      if (!t || !t.closest) return;
      var card = t.closest('a.card');
      if (card) {
        var href = card.getAttribute('href') || '';
        if (href.charAt(0) === '#') { e.preventDefault(); openQuery(href.slice(1)); }
        return;
      }
      var sm = t.closest('summary');
      if (sm) {
        var d = sm.parentElement;
        if (d && d.classList.contains('panel')) buildPanel(d);
      }
    });

    document.querySelectorAll('.toolbar .tbtn').forEach(function (b) {
      b.addEventListener('click', function () {
        var open = b.dataset.act === 'open';
        var sec = sections[current];
        buildSection(sec);
        [].slice.call(sec.querySelectorAll('details')).forEach(function (d) {
          if (open) buildPanel(d);
          d.open = open;
        });
      });
    });

    // print reveals every project (CSS), so build everything and open all panels
    var reopened = [];
    window.addEventListener('beforeprint', function () {
      sections.forEach(buildSection);
      var all = [].slice.call(stage.querySelectorAll('details'));
      all.forEach(buildPanel);
      reopened = all.filter(function (d) { return !d.open; });
      reopened.forEach(function (d) { d.open = true; });
    });
    window.addEventListener('afterprint', function () {
      reopened.forEach(function (d) { d.open = false; });
      reopened = [];
    });

    // initial route: a #p<id>q<n> link opens that query; #p<id> just selects the tab
    var mq = /^#p(\d+)q(\d+)$/.exec(location.hash);
    if (mq) {
      openQuery(location.hash.slice(1));
    } else {
      var mp = /^#p([1-9])/.exec(location.hash);
      show(mp ? Math.min(+mp[1], tabs.length) - 1 : 0, false);
    }
  }

  /* The data arrives as three <script src="data/*.js"> globals rather than via
     fetch(). Script tags are exempt from the file:// restriction that blocks
     fetch, so the page renders identically opened from a folder or over HTTP. */
  try {
    var missing = ['__META__', '__SCHEMA__', '__RESULTS__'].filter(function (k) {
      return !window[k];
    });
    if (missing.length) {
      throw new Error('data script(s) did not load: ' +
        missing.map(function (k) { return k.replace(/_/g, '').toLowerCase() + '.js'; }).join(', '));
    }
    render(window.__META__, window.__SCHEMA__, window.__RESULTS__);
  } catch (err) {
    document.getElementById('stage').innerHTML =
      '<p class="loading" role="alert"><strong>Could not render the page.</strong><br>' + esc(err.message) +
      '<br><br>Check that <code>docs/data/</code> sits next to this file and contains ' +
      '<code>meta.js</code>, <code>schema.js</code> and <code>results.js</code>. ' +
      'Regenerate them with the site build script.</p>';
  }
})();
