let apiData = null;
let isDark = false;
let searchQuery = '';
let authHeader = '';
const responses = {};
const loading = {};
const requestBodyValues = {};
const expandedEndpoints = {};
const expandedQuery = {};
const expandedHeaders = {};

const methodColors = {
    GET: '#61affe',
    POST: '#49cc90',
    PUT: '#fca130',
    DELETE: '#f93e3e',
    PATCH: '#50e3c2'
};

async function loadData() {
    try {
        const resp = await fetch('/froggy_docs.json');
        if (resp.ok) {
            const newData = await resp.json();
            if (apiData && JSON.stringify(apiData) !== JSON.stringify(newData)) {
                showHotReloadToast();
            }
            apiData = newData;
            render();
        }
    } catch (e) {
        console.error('Failed to load API data:', e);
    }
}

function showHotReloadToast() {
    let toast = document.getElementById('hot-reload-toast');
    if (!toast) {
        toast = document.createElement('div');
        toast.id = 'hot-reload-toast';
        toast.className = 'toast';
        document.body.appendChild(toast);
    }
    toast.textContent = '🔄 Spec hot-reloaded!';
    toast.style.display = 'block';
    clearTimeout(toast._timer);
    toast._timer = setTimeout(() => { toast.style.display = 'none'; }, 3000);
}

function getEndpointsByTag() {
    const byTag = {};
    const paths = apiData?.paths || {};
    for (const [path, methods] of Object.entries(paths)) {
        for (const [method, spec] of Object.entries(methods)) {
            const tags = spec.tags || ['Untagged'];
            for (const tag of tags) {
                if (!byTag[tag]) byTag[tag] = [];
                byTag[tag].push({ path, method, spec });
            }
        }
    }
    return byTag;
}

function render() {
    document.getElementById('docTitle').textContent = apiData?.info?.title || 'API Documentation';
    renderSidebar();
    renderApiList();
}

function renderSidebar() {
    const byTag = getEndpointsByTag();
    const filtered = Object.entries(byTag).filter(([tag, endpoints]) => {
        if (searchQuery === '') return true;
        if (tag.toLowerCase().includes(searchQuery.toLowerCase())) return true;
        return endpoints.some(ep => ep.path.toLowerCase().includes(searchQuery.toLowerCase()));
    });

    let html = '';
    for (const [tag, endpoints] of filtered) {
        const tagMatchesSearch = searchQuery === '' || tag.toLowerCase().includes(searchQuery.toLowerCase());
        const tagFiltered = tagMatchesSearch
            ? endpoints
            : endpoints.filter(ep => ep.path.toLowerCase().includes(searchQuery.toLowerCase()));

        if (searchQuery !== '' && tagFiltered.length === 0) continue;

        html += `
            <div class="tag-group">
                <div class="tag-header">▶ ${tag}</div>
                <div class="tag-endpoints">
                    ${tagFiltered.map(ep => `
                        <a class="nav-item" href="#${ep.method.toUpperCase()}-${ep.path}">
                            <span class="method-tag ${ep.method.toUpperCase()}" style="background:${methodColors[ep.method.toUpperCase()] || '#666'}">${ep.method.toUpperCase()}</span>
                            <span>${ep.path}</span>
                        </a>
                    `).join('')}
                </div>
            </div>
        `;
    }
    document.getElementById('navList').innerHTML = html;
}

function renderApiList() {
    if (!apiData) {
        document.getElementById('apiList').innerHTML = '<div class="api-section"><p>Loading...</p></div>';
        return;
    }

    const paths = apiData.paths || {};
    let html = '';
    for (const [path, methods] of Object.entries(paths)) {
        for (const [method, spec] of Object.entries(methods)) {
            html += renderEndpoint(path, method, spec);
        }
    }
    document.getElementById('apiList').innerHTML = html;
}

function getBodyProps(spec) {
    const jsonProps = spec.requestBody?.content?.['application/json']?.schema?.properties;
    const multipartProps = spec.requestBody?.content?.['multipart/form-data']?.schema?.properties;
    return { props: jsonProps || multipartProps, hasFiles: !!multipartProps };
}

function renderFormField(key, name, prop) {
    const isFile = prop.format === 'binary';
    const savedValue = (requestBodyValues[key] || {})[name] || '';
    return `
        <div class="form-field">
            <label>${name} (${isFile ? 'file' : (prop.type || 'string')})</label>
            ${prop.description ? `<span class="field-desc">${prop.description}</span>` : ''}
            ${isFile
                ? `<input type="file" class="form-input file-input" id="file-${key}-${name}">`
                : `<input type="text" class="form-input"
                       placeholder="${prop.default || ''}"
                       value="${savedValue}"
                       oninput="saveBodyValue('${key}', '${name}', this.value)">`
            }
        </div>
    `;
}

function renderQuerySection(key, params) {
    if (!params || params.length === 0) return '';
    const isExpanded = expandedQuery[key] || false;
    return `
        <div class="query-section">
            <button class="collapsible-btn" onclick="toggleQuery('${key}')">
                ${isExpanded ? '▲' : '▼'} Query Params
            </button>
            ${isExpanded ? `
                <div class="params-form">
                    ${params.map(qp => {
                        const savedVal = (requestBodyValues[`query-${key}`] || {})[qp.name] || '';
                        const defaultVal = qp.schema?.default ?? '';
                        return `
                            <div class="form-field">
                                <label>${qp.name} (${qp.schema?.type || 'string'})</label>
                                ${qp.description ? `<span class="field-desc">${qp.description}</span>` : ''}
                                <input type="text" class="form-input"
                                    placeholder="${defaultVal}"
                                    value="${savedVal}"
                                    oninput="saveQueryValue('${key}', '${qp.name}', this.value)">
                            </div>
                        `;
                    }).join('')}
                </div>
            ` : ''}
        </div>
    `;
}

function renderHeadersSection(key, params) {
    if (!params || params.length === 0) return '';
    const isExpanded = expandedHeaders[key] || false;
    return `
        <div class="headers-section">
            <button class="collapsible-btn" onclick="toggleHeaders('${key}')">
                ${isExpanded ? '▲' : '▼'} Headers
            </button>
            ${isExpanded ? `
                <div class="params-form">
                    ${params.map(hp => {
                        const savedVal = (requestBodyValues[`header-${key}`] || {})[hp.name] || '';
                        return `
                            <div class="form-field">
                                <label>${hp.name} (${hp.schema?.type || 'string'})</label>
                                ${hp.description ? `<span class="field-desc">${hp.description}</span>` : ''}
                                <input type="text" class="form-input"
                                    value="${savedVal}"
                                    oninput="saveHeaderValue('${key}', '${hp.name}', this.value)">
                            </div>
                        `;
                    }).join('')}
                </div>
            ` : ''}
        </div>
    `;
}

function renderResponseSchemas(responses) {
    if (!responses) return '';
    const entries = Object.entries(responses);
    if (entries.length === 0) return '';
    return `
        <div class="response-schemas">
            <h3 class="section-title">Responses</h3>
            ${entries.map(([code, resp]) => {
                const content = resp.content?.['application/json'];
                const schemaType = content?.schema?.type || 'object';
                const example = content?.example;
                return `
                    <div class="response-schema">
                        <div class="response-code">${code} - ${resp.description || ''}</div>
                        ${content ? `<div class="schema-type">Type: ${schemaType}</div>` : ''}
                        ${example != null ? `<pre class="schema-example">${JSON.stringify(example, null, 2)}</pre>` : ''}
                    </div>
                `;
            }).join('')}
        </div>
    `;
}

function renderEndpoint(path, method, spec) {
    const key = `${method}-${path}`;
    const { props, hasFiles } = getBodyProps(spec);
    const hasAuth = spec.security != null;
    const isExpanded = expandedEndpoints[key] || false;

    const queryParams = (spec.parameters || []).filter(p => p.in === 'query');
    const headerParams = (spec.parameters || []).filter(p => p.in === 'header');

    const formHtml = props && Object.keys(props).length > 0 ? `
        <button class="try-it-out-btn ${isExpanded ? '' : 'secondary'}" onclick="toggleBody('${key}')">
            ${isExpanded ? 'Hide Request Body' : 'Show Request Body'}
        </button>
        ${isExpanded ? `
            <h3 class="section-title">${hasFiles ? 'Multipart Form Data' : 'Request Body'}</h3>
            <div class="request-body-form">
                ${Object.entries(props).map(([name, prop]) => renderFormField(key, name, prop)).join('')}
            </div>
        ` : ''}
    ` : '';

    const propsJson = props ? JSON.stringify(props).replace(/"/g, '&quot;') : 'null';
    const hasFilesStr = hasFiles ? 'true' : 'false';

    return `
        <section class="api-section" id="${method.toUpperCase()}-${path}">
            <div class="endpoint-header">
                <span class="method-tag ${method.toUpperCase()}" style="background:${methodColors[method.toUpperCase()] || '#666'}">${method.toUpperCase()}</span>
                <span class="path-text">${path}</span>
                ${hasAuth ? '<span class="auth-badge">🔒 Auth</span>' : ''}
            </div>
            <p class="api-description">${spec.summary || 'No description'}</p>

            ${formHtml}
            ${renderQuerySection(key, queryParams)}
            ${renderHeadersSection(key, headerParams)}
            ${renderResponseSchemas(spec.responses)}

            <button class="try-it-out-btn" onclick="executeRequest('${method}', '${path}', ${hasAuth}, ${propsJson}, ${hasFilesStr})">
                ${loading[key] ? 'Loading...' : 'Try It Out'}
            </button>

            ${responses[key] ? `
                <div class="response-section">
                    <h4>Response:</h4>
                    <pre class="response-body">${escapeHtml(responses[key])}</pre>
                </div>
            ` : ''}
        </section>
    `;
}

function escapeHtml(str) {
    return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function toggleBody(key) {
    expandedEndpoints[key] = !expandedEndpoints[key];
    renderApiList();
}

function toggleQuery(key) {
    expandedQuery[key] = !expandedQuery[key];
    renderApiList();
}

function toggleHeaders(key) {
    expandedHeaders[key] = !expandedHeaders[key];
    renderApiList();
}

function saveBodyValue(key, field, value) {
    if (!requestBodyValues[key]) requestBodyValues[key] = {};
    requestBodyValues[key][field] = value;
}

function saveQueryValue(key, field, value) {
    const qKey = `query-${key}`;
    if (!requestBodyValues[qKey]) requestBodyValues[qKey] = {};
    requestBodyValues[qKey][field] = value;
}

function saveHeaderValue(key, field, value) {
    const hKey = `header-${key}`;
    if (!requestBodyValues[hKey]) requestBodyValues[hKey] = {};
    requestBodyValues[hKey][field] = value;
}

async function executeRequest(method, path, hasAuth, props, hasFiles) {
    const key = `${method}-${path}`;
    loading[key] = true;
    renderApiList();

    try {
        const headers = {};
        if (authHeader) headers['Authorization'] = authHeader;

        // Add saved custom headers
        const savedHeaders = requestBodyValues[`header-${key}`] || {};
        for (const [name, val] of Object.entries(savedHeaders)) {
            if (val) headers[name] = val;
        }

        // Build URL with query params
        let url = `${window.location.origin}${path}`;
        const savedQuery = requestBodyValues[`query-${key}`] || {};
        const queryParts = Object.entries(savedQuery).filter(([, v]) => v);
        if (queryParts.length > 0) {
            url += '?' + queryParts.map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`).join('&');
        }

        let resp;

        if (hasFiles && props) {
            // Multipart: use FormData to carry both text fields and file inputs
            const formData = new FormData();
            for (const [name, prop] of Object.entries(props)) {
                if (prop.format === 'binary') {
                    const fileInput = document.getElementById(`file-${key}-${name}`);
                    if (fileInput && fileInput.files && fileInput.files[0]) {
                        formData.append(name, fileInput.files[0]);
                    }
                } else {
                    const val = (requestBodyValues[key] || {})[name] || prop.default || '';
                    if (val) formData.append(name, val);
                }
            }
            resp = await fetch(url, { method, headers, body: formData });
        } else {
            headers['Content-Type'] = 'application/json';
            let body;
            if (props && method !== 'GET' && method !== 'HEAD') {
                const bodyData = {};
                const savedValues = requestBodyValues[key] || {};
                for (const [name, prop] of Object.entries(props)) {
                    const value = savedValues[name] || prop.default || '';
                    if (value) bodyData[name] = prop.type === 'number' ? Number(value) : value;
                }
                body = JSON.stringify(bodyData);
            }
            resp = await fetch(url, { method, headers, body });
        }

        let responseText;
        try {
            const json = await resp.json();
            responseText = JSON.stringify(json, null, 2);
        } catch {
            responseText = await resp.text();
        }

        responses[key] = resp.ok ? responseText : `Error ${resp.status}: ${responseText}`;
    } catch (e) {
        responses[key] = `Error: ${e.message}`;
    }

    loading[key] = false;
    renderApiList();
}

document.getElementById('searchInput').addEventListener('input', (e) => {
    searchQuery = e.target.value;
    render();
});

document.getElementById('authInput').addEventListener('input', (e) => {
    authHeader = e.target.value;
});

document.getElementById('themeToggle').addEventListener('click', () => {
    isDark = !isDark;
    document.documentElement.setAttribute('data-theme', isDark ? 'dark' : 'light');
    document.getElementById('themeToggle').textContent = isDark ? '☀️' : '🌙';
});

if (window.matchMedia('(prefers-color-scheme: dark)').matches) {
    isDark = true;
    document.documentElement.setAttribute('data-theme', 'dark');
    document.getElementById('themeToggle').textContent = '☀️';
}

loadData();
setInterval(loadData, 3000);
