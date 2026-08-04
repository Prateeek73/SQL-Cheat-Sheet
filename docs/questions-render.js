const LEVELS = ['Beginner', 'Intermediate', 'Advanced', 'Extended'];
const STATE = { projects: [], activeProjectIndex: 0 };

function getKeyBadge(key) {
  switch (key) {
    case 'primary':
      return 'PK';
    case 'foreign':
      return 'FK';
    case 'conjunction':
    case 'composite':
      return 'CJ';
    default:
      return null;
  }
}

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

async function fetchJson(candidateUrls) {
  let lastError = null;
  for (const url of candidateUrls) {
    try {
      const response = await fetch(url);
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`);
      }
      return await response.json();
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError || new Error('Unable to load data');
}

function buildDataCandidates(fileName) {
  const candidates = [];
  const add = (value) => {
    if (!value) {
      return;
    }
    const url = new URL(value, window.location.href);
    candidates.push(url.toString());
  };

  add(`./${fileName}`);
  add(`./docs/${fileName}`);
  add(`../${fileName}`);
  add(`/${fileName}`);
  add(`/docs/${fileName}`);

  const currentPage = new URL(window.location.href);
  const currentPath = currentPage.pathname.replace(/[^/]+$/, '');
  add(currentPath + fileName);
  add(currentPath + `docs/${fileName}`);

  return Array.from(new Set(candidates));
}

function countQuestionsByLevel(project) {
  return LEVELS.reduce((acc, level) => {
    acc[level] = project.questions.filter((q) => q.level === level).length;
    return acc;
  }, {});
}

function createProjectTab(project, index) {
  const button = document.createElement('button');
  button.className = 'tab';
  button.type = 'button';
  button.setAttribute('role', 'tab');
  button.setAttribute('aria-selected', index === STATE.activeProjectIndex ? 'true' : 'false');
  button.setAttribute('aria-controls', `panel-${project.slug}`);
  button.dataset.index = String(index);
  button.innerHTML = `
    <span class="tnum">${index + 1}</span>
    <span class="tname">${escapeHtml(project.title)}</span>
    <span class="tcount">${project.questionCount}</span>
  `;
  button.addEventListener('click', () => selectProject(index));
  return button;
}

function createSchemaBlock(projectSchema) {
  if (!projectSchema || !projectSchema.tables || !projectSchema.tables.length) {
    return null;
  }

  const shell = document.createElement('section');
  shell.className = 'schema-shell';
  shell.innerHTML = `
    <div class="schema-head">
      <h3>Schema snapshot</h3>
      <p>${escapeHtml(projectSchema.summary || 'Key columns are highlighted so it is easy to spot the main joins.')}</p>
    </div>
    <div class="schema-grid"></div>
  `;

  const grid = shell.querySelector('.schema-grid');
  projectSchema.tables.forEach((table) => {
    const card = document.createElement('article');
    card.className = 'schema-card';
    card.innerHTML = `
      <h4>${escapeHtml(table.table)}</h4>
      <ul class="schema-fields"></ul>
    `;
    const list = card.querySelector('.schema-fields');
    (table.columns || []).forEach((column) => {
      const badge = getKeyBadge(column.key);
      const item = document.createElement('li');
      item.className = badge ? `schema-field schema-field-${column.key}` : 'schema-field';
      item.innerHTML = `
        <span class="field-name">${escapeHtml(column.name)}</span>
        <span class="field-type">${escapeHtml(column.type || '')}</span>
        ${badge ? `<span class="key-badge">${escapeHtml(badge)}</span>` : ''}
      `;
      if (column.references) {
        const ref = document.createElement('span');
        ref.className = 'field-ref';
        ref.textContent = column.references;
        item.appendChild(ref);
      }
      list.appendChild(item);
    });
    grid.appendChild(card);
  });

  return shell;
}

function createProjectSection(project, index, projectSchema) {
  const section = document.createElement('section');
  section.className = 'project';
  section.id = `panel-${project.slug}`;
  section.hidden = index !== STATE.activeProjectIndex;
  section.setAttribute('role', 'tabpanel');
  section.setAttribute('aria-labelledby', `tab-${project.slug}`);

  const header = document.createElement('header');
  header.className = 'phead';
  header.innerHTML = `
    <div class="pnum">${index + 1}</div>
    <div>
      <h2>${escapeHtml(project.title)}</h2>
      <p class="meta"><code>${escapeHtml(project.database)}</code> · ${project.rows.toLocaleString()} rows · <span class="kag">${escapeHtml(project.source)}</span></p>
    </div>
  `;
  section.appendChild(header);

  const intro = document.createElement('div');
  intro.className = 'project-intro';
  intro.innerHTML = `
    <p>Questions are loaded from <code>${escapeHtml(project.sqlFile)}</code> in the repository. The page reads the SQL directly from that file so you do not need to hard-code every query into the page.</p>
  `;
  section.appendChild(intro);

  const schemaBlock = createSchemaBlock(projectSchema);
  if (schemaBlock) {
    section.appendChild(schemaBlock);
  }

  for (const level of LEVELS) {
    const questions = project.questions.filter((q) => q.level === level);
    if (!questions.length) {
      continue;
    }
    const levelBlock = document.createElement('div');
    levelBlock.className = 'level-block';
    levelBlock.innerHTML = `
      <div class="lvlhead lvl-${level.toLowerCase()}">
        <h3>${escapeHtml(level)} <span class="count">${questions.length}</span></h3>
      </div>
      <div class="card-grid"></div>
    `;
    const grid = levelBlock.querySelector('.card-grid');
    questions.forEach((question, questionIndex) => {
      const item = document.createElement('details');
      item.className = 'question-card';
      item.id = `q-${project.slug}-${question.number}`;
      item.innerHTML = `
        <summary>
          <span class="qn">Q${question.number}</span>
          <span class="q">${escapeHtml(question.title)}</span>
          <span class="file">${escapeHtml(project.sqlFile)}<span class="go">Open SQL</span></span>
        </summary>
        <div class="question-body">
          <div class="question-toolbar">
            <p class="question-meta">Loaded from <code>${escapeHtml(project.sqlFile)}</code> · question ${question.number}</p>
            <button class="copy-sql" type="button">Copy SQL</button>
          </div>
          <pre class="sql">${escapeHtml(question.sql || 'No SQL available for this question.')}</pre>
        </div>
      `;
      const copyButton = item.querySelector('.copy-sql');
      if (copyButton) {
        copyButton.addEventListener('click', (event) => {
          event.preventDefault();
          event.stopPropagation();
          copySqlToClipboard(item.querySelector('pre.sql'));
        });
      }
      grid.appendChild(item);
    });
    section.appendChild(levelBlock);
  }

  return section;
}

function copySqlToClipboard(pre) {
  if (!pre) {
    return;
  }
  const sqlText = pre.textContent || '';
  const button = pre.closest('.question-body')?.querySelector('.copy-sql');
  const originalText = button ? button.textContent : 'Copy SQL';

  const copyWithFallback = () => {
    const textarea = document.createElement('textarea');
    textarea.value = sqlText;
    textarea.setAttribute('readonly', '');
    textarea.style.position = 'fixed';
    textarea.style.left = '-9999px';
    document.body.appendChild(textarea);
    textarea.select();
    document.execCommand('copy');
    document.body.removeChild(textarea);
  };

  if (navigator.clipboard && navigator.clipboard.writeText) {
    navigator.clipboard.writeText(sqlText).then(() => {
      if (button) {
        button.textContent = 'Copied';
        window.setTimeout(() => { button.textContent = originalText; }, 1200);
      }
    }).catch(() => {
      copyWithFallback();
      if (button) {
        button.textContent = 'Copied';
        window.setTimeout(() => { button.textContent = originalText; }, 1200);
      }
    });
    return;
  }

  copyWithFallback();
  if (button) {
    button.textContent = 'Copied';
    window.setTimeout(() => { button.textContent = originalText; }, 1200);
  }
}

function selectProject(index) {
  STATE.activeProjectIndex = index;
  const tabs = Array.from(document.querySelectorAll('.tabs .tab'));
  tabs.forEach((tab, idx) => {
    const selected = idx === index;
    tab.setAttribute('aria-selected', selected ? 'true' : 'false');
    tab.classList.toggle('active', selected);
  });
  document.querySelectorAll('.project').forEach((section, idx) => {
    section.hidden = idx !== index;
  });
  const hash = `#p-${STATE.projects[index].slug}`;
  history.replaceState(null, '', hash);
}

function render(data, schemaData) {
  STATE.projects = data.projects;
  const tabs = document.getElementById('tabs');
  const projectsHost = document.getElementById('projects');
  const schemaIndex = new Map((schemaData.projects || []).map((schemaProject) => [schemaProject.slug, schemaProject]));

  const projectCount = document.getElementById('project-count');
  projectCount.textContent = String(data.projects.length);

  const questionCount = document.getElementById('question-count');
  questionCount.textContent = String(data.projects.reduce((sum, project) => sum + project.questionCount, 0));

  const totalRows = document.getElementById('source-rows');
  totalRows.textContent = data.projects.reduce((sum, project) => sum + project.rows, 0).toLocaleString();

  const tabList = document.createElement('div');
  tabList.className = 'tab-list';
  data.projects.forEach((project, index) => {
    const button = createProjectTab(project, index);
    button.id = `tab-${project.slug}`;
    tabList.appendChild(button);
  });
  tabs.innerHTML = '';
  tabs.appendChild(tabList);

  projectsHost.innerHTML = '';
  data.projects.forEach((project, index) => {
    const projectSchema = schemaIndex.get(project.slug);
    projectsHost.appendChild(createProjectSection(project, index, projectSchema));
  });

  const initialIndex = parseInitialProjectIndex();
  selectProject(initialIndex);
}

function parseInitialProjectIndex() {
  const params = new URLSearchParams(window.location.hash.replace(/^#/, ''));
  const slug = params.get('project');
  if (slug) {
    const index = STATE.projects.findIndex((project) => project.slug === slug);
    if (index >= 0) {
      return index;
    }
  }
  const hashMatch = /^#p-(.+)$/.exec(window.location.hash);
  if (hashMatch) {
    const index = STATE.projects.findIndex((project) => project.slug === hashMatch[1]);
    if (index >= 0) {
      return index;
    }
  }
  return 0;
}

function wireToolbar() {
  const buttons = document.querySelectorAll('.toolbar .tbtn');
  buttons.forEach((button) => {
    button.addEventListener('click', () => {
      const action = button.dataset.action;
      const all = document.querySelectorAll('.question-card');
      all.forEach((card) => {
        card.open = action === 'expand';
      });
    });
  });
}

(async function boot() {
  try {
    const [data, schemaData] = await Promise.all([
      fetchJson(buildDataCandidates('questions-data.json')),
      fetchJson(buildDataCandidates('project-schemas.json'))
    ]);
    render(data, schemaData);
    wireToolbar();
  } catch (error) {
    const host = document.getElementById('projects');
    host.innerHTML = `<p class="error">Unable to load the page data from the published docs files. ${escapeHtml(error.message)}</p>`;
  }
})();
