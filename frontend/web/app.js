let apiData = null;
let isDark = false;
let isSidebarCollapsed = false;
let currentView = 'docs';
let isTokenVisible = false;
let searchQuery = '';
let authHeader = '';
let apiServers = [];
let selectedServerIndex = 0;
let rawSpec = null;
let isLoadingSpec = false;
const REQUEST_TIMEOUT_MS = 30000;
const MAX_FILE_BYTES = 25 * 1024 * 1024;
const responses = {};
const responseMedia = {};
const loading = {};
const requestBodyValues = {};
const activeEndpointTabs = {};
const activeExampleLanguages = {};
let activeEndpointId = '';
let endpointObserver = null;

async function loadData() {
    if (isLoadingSpec) return;
    isLoadingSpec = true;
    try {
        const specUrl = new URL('froggy_docs.json', document.baseURI);
        const { response: resp, text: nextRawSpec } = await fetchTextWithTimeout(specUrl);
        if (resp.ok) {
            if (nextRawSpec !== rawSpec) {
                const newData = JSON.parse(nextRawSpec);
                if (rawSpec !== null) showHotReloadToast();
                rawSpec = nextRawSpec;
                apiData = newData;
                configureApiServers();
                render();
            }
        }
    } catch (e) {
        console.error('Failed to load API data:', e);
    } finally {
        isLoadingSpec = false;
    }
}

function configureApiServers() {
    const configured = Array.isArray(apiData?.servers) ? apiData.servers : [];
    apiServers = configured.length ? configured.map((server, index) => ({
        name: server['x-name'] || server.description || `Environment ${index + 1}`,
        url: server.url || window.location.origin,
        environment: String(server['x-environment'] || 'development').toLowerCase(),
        readOnly: server['x-read-only'] === true,
        confirmMutations: server['x-confirm-mutations'] === true
    })) : [{
        name: 'Current server',
        url: window.location.origin,
        environment: 'development',
        readOnly: false,
        confirmMutations: false
    }];

    const defaultEnvironment = apiData?.['x-froggy-docs']?.defaultEnvironment || '';
    let savedEnvironment = '';
    try {
        savedEnvironment = localStorage.getItem('froggy-docs-environment') || '';
    } catch {
        // Environment selection still works when persistent storage is blocked.
    }
    const preferred = savedEnvironment || defaultEnvironment;
    const preferredIndex = apiServers.findIndex(server =>
        server.name === preferred || server.environment === preferred);
    selectedServerIndex = preferredIndex >= 0 ? preferredIndex : 0;
    renderEnvironmentSelector();
}

function selectedApiServer() {
    return apiServers[selectedServerIndex] || {
        name: 'Current server',
        url: window.location.origin,
        environment: 'development',
        readOnly: false,
        confirmMutations: false
    };
}

function apiBaseUrl() {
    const configuredUrl = selectedApiServer().url;
    return new URL(configuredUrl, window.location.origin).toString().replace(/\/$/, '');
}

function renderEnvironmentSelector() {
    const control = document.getElementById('environmentControl');
    const select = document.getElementById('environmentSelect');
    if (!control || !select) return;
    control.hidden = apiServers.length < 2;
    select.innerHTML = apiServers.map((server, index) => `
        <option value="${index}" ${index === selectedServerIndex ? 'selected' : ''}>${escapeHtml(server.name)}</option>
    `).join('');
    updateEnvironmentWarning();
}

function updateEnvironmentWarning() {
    const warning = document.getElementById('environmentWarning');
    if (!warning) return;
    const server = selectedApiServer();
    const isProtected = server.environment === 'production' || server.readOnly;
    warning.hidden = !isProtected;
    warning.classList.toggle('is-read-only', server.readOnly);
    warning.textContent = server.readOnly
        ? `${server.name} is read-only. Mutating requests are disabled.`
        : `${server.name} is a production environment. Mutating requests require confirmation.`;
}

function selectApiEnvironment(index) {
    selectedServerIndex = Number(index) || 0;
    const server = selectedApiServer();
    try {
        localStorage.setItem('froggy-docs-environment', server.name);
    } catch {
        // Keep the selection for this page even when storage is unavailable.
    }
    updateEnvironmentWarning();
    renderApiList();
    observeEndpoints();
}

async function fetchTextWithTimeout(url, options = {}) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
    try {
        const response = await fetch(url, { ...options, signal: controller.signal });
        const text = await response.text();
        return { response, text };
    } finally {
        clearTimeout(timeout);
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
    toast.textContent = 'API specification updated';
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
    const paths = apiData?.paths || {};
    const endpointTotal = Object.values(paths)
        .reduce((total, methods) => total + Object.keys(methods).length, 0);
    document.getElementById('docTitle').textContent = apiData?.info?.title || 'API Documentation';
    document.getElementById('docDescription').textContent = apiData?.info?.description
        || 'Explore endpoints, inspect schemas, and send test requests.';
    document.getElementById('endpointCount').textContent = `${endpointTotal} endpoint${endpointTotal === 1 ? '' : 's'}`;
    renderSidebar();
    renderApiList();
    observeEndpoints();
}

function endpointSearchText(path, method, spec) {
    return [
        path,
        method,
        spec.summary || '',
        spec.description || '',
        ...(spec.tags || [])
    ].join(' ').toLowerCase();
}

function renderSidebar() {
    const byTag = getEndpointsByTag();
    const filtered = Object.entries(byTag).filter(([tag, endpoints]) => {
        if (searchQuery === '') return true;
        if (tag.toLowerCase().includes(searchQuery.toLowerCase())) return true;
        return endpoints.some(ep => endpointSearchText(ep.path, ep.method, ep.spec)
            .includes(searchQuery.toLowerCase()));
    });

    let html = '';
    for (const [tag, endpoints] of filtered) {
        const tagMatchesSearch = searchQuery === '' || tag.toLowerCase().includes(searchQuery.toLowerCase());
        const tagFiltered = tagMatchesSearch
            ? endpoints
            : endpoints.filter(ep => endpointSearchText(ep.path, ep.method, ep.spec)
                .includes(searchQuery.toLowerCase()));

        if (searchQuery !== '' && tagFiltered.length === 0) continue;

        html += `
            <div class="tag-group">
                <div class="tag-header">
                    <span>${escapeHtml(tag)}</span>
                    <span class="tag-count">${tagFiltered.length}</span>
                </div>
                <div class="tag-endpoints">
                    ${tagFiltered.map(ep => `
                        <a class="nav-item ${activeEndpointId === `${ep.method.toUpperCase()}-${ep.path}` ? 'is-active' : ''}"
                           href="#${ep.method.toUpperCase()}-${ep.path}"
                           data-endpoint-id="${escapeHtml(`${ep.method.toUpperCase()}-${ep.path}`)}">
                            <span class="method-tag ${ep.method.toUpperCase()}">${ep.method.toUpperCase()}</span>
                            <span class="nav-path">${escapeHtml(ep.path)}</span>
                        </a>
                    `).join('')}
                </div>
            </div>
        `;
    }
    if (!html) {
        html = '<div class="empty-state">No matching endpoints</div>';
    }
    document.getElementById('navList').innerHTML = html;
}

function renderApiList() {
    if (!apiData) {
        document.getElementById('apiList').innerHTML = '<div class="loading-state">Loading API specification</div>';
        return;
    }

    const paths = apiData.paths || {};
    let html = '';
    for (const [path, methods] of Object.entries(paths)) {
        for (const [method, spec] of Object.entries(methods)) {
            const searchableText = endpointSearchText(path, method, spec);
            if (searchQuery && !searchableText.includes(searchQuery.toLowerCase())) continue;
            html += renderEndpoint(path, method, spec);
        }
    }
    if (!html) {
        html = `<div class="empty-state">${searchQuery
            ? 'No endpoints match your search.'
            : 'No endpoints are available in this specification.'}</div>`;
    }
    document.getElementById('apiList').innerHTML = html;
    observeEndpoints();
}

function getBodyDefinition(spec) {
    const content = spec.requestBody?.content || {};
    const contentType = content['application/json']
        ? 'application/json'
        : (content['multipart/form-data'] ? 'multipart/form-data' : Object.keys(content)[0]);
    const schema = contentType ? content[contentType]?.schema : null;
    return {
        props: schema?.properties,
        required: new Set(schema?.required || []),
        hasFiles: contentType === 'multipart/form-data',
        contentType: contentType || null
    };
}

function isFileProperty(prop) {
    return prop?.format === 'binary'
        || (prop?.type === 'array' && prop?.items?.format === 'binary');
}

function isMultiFileProperty(prop) {
    return prop?.type === 'array' && prop?.items?.format === 'binary';
}

function renderFormField(key, name, prop, required = false) {
    const isFile = isFileProperty(prop);
    const isMultiple = isMultiFileProperty(prop);
    const savedValue = (requestBodyValues[key] || {})[name] || '';
    return `
        <div class="form-field parameter-field">
            <div class="field-heading">
                <label>${escapeHtml(name)}${required ? '<span class="required-mark">*</span>' : ''}</label>
                <span class="field-type">${isFile ? (isMultiple ? 'files' : 'file') : escapeHtml(prop.type || 'string')}</span>
                <span class="requirement-badge ${required ? 'is-required' : ''}">${required ? 'Required' : 'Optional'}</span>
            </div>
            ${prop.description ? `<span class="field-desc">${escapeHtml(prop.description)}</span>` : '<span class="field-desc">No description provided</span>'}
            ${prop.default != null ? `<span class="field-default">Default: <code>${escapeHtml(prop.default)}</code></span>` : ''}
            ${isFile
                ? `<input type="file" class="form-input file-input" id="file-${key}-${name}" ${isMultiple ? 'multiple' : ''}>`
                : `<input type="text" class="form-input"
                       placeholder="${escapeHtml(prop.default || '')}"
                       value="${escapeHtml(savedValue)}"
                       oninput="saveBodyValue('${key}', '${name}', this.value)">`
            }
        </div>
    `;
}

function renderParameterGroup(key, title, params, location) {
    if (!params?.length) return '';
    return `
        <section class="parameter-group">
            <div class="section-heading-row">
                <h3 class="section-title">${title}</h3>
                <span class="section-count">${params.length}</span>
            </div>
            <div class="params-form">
                ${params.map(param => {
                    const storeKey = `${location}-${key}`;
                    const savedVal = (requestBodyValues[storeKey] || {})[param.name] || '';
                    const defaultVal = param.schema?.default ?? '';
                    const saveHandler = location === 'path'
                        ? 'savePathValue'
                        : (location === 'query' ? 'saveQueryValue' : 'saveHeaderValue');
                    return `
                        <div class="form-field parameter-field">
                            <div class="field-heading">
                                <label>${escapeHtml(param.name)}${param.required ? '<span class="required-mark">*</span>' : ''}</label>
                                <span class="field-type">${escapeHtml(param.schema?.type || 'string')}</span>
                                <span class="requirement-badge ${param.required ? 'is-required' : ''}">${param.required ? 'Required' : 'Optional'}</span>
                            </div>
                            ${param.description ? `<span class="field-desc">${escapeHtml(param.description)}</span>` : '<span class="field-desc">No description provided</span>'}
                            ${defaultVal !== '' ? `<span class="field-default">Default: <code>${escapeHtml(defaultVal)}</code></span>` : ''}
                            <input type="text" class="form-input"
                                placeholder="${defaultVal !== '' ? escapeHtml(defaultVal) : `Enter ${escapeHtml(param.name)}`}"
                                value="${escapeHtml(savedVal)}"
                                oninput="${saveHandler}('${key}', '${param.name}', this.value)">
                        </div>
                    `;
                }).join('')}
            </div>
        </section>
    `;
}

function responseTone(code) {
    const number = Number(code);
    if (number >= 200 && number < 300) return 'success';
    if (number >= 400 && number < 500) return 'warning';
    if (number >= 500) return 'error';
    return 'neutral';
}

function renderCodeBlock(title, code, language = '') {
    return `
        <div class="code-block">
            <div class="code-block-heading">
                <span>${escapeHtml(title)}</span>
                <button type="button" class="code-copy-btn" onclick="copyCode(this)" aria-label="Copy ${escapeHtml(title)}">Copy</button>
            </div>
            <pre class="schema-example" data-language="${escapeHtml(language)}">${escapeHtml(code)}</pre>
        </div>
    `;
}

function renderResponseSchemas(responseDefinitions) {
    if (!responseDefinitions) return '';
    const entries = Object.entries(responseDefinitions);
    if (entries.length === 0) return '';
    return `
        <div class="response-schemas">
            ${entries.map(([code, resp]) => {
                const content = resp.content?.['application/json'];
                const schemaType = content?.schema?.type || 'object';
                const example = content?.example;
                const tone = responseTone(code);
                return `
                    <details class="response-schema response-${tone}">
                        <summary>
                            <span class="status-indicator"></span>
                            <span class="response-status-code">${escapeHtml(code)}</span>
                            <span class="response-description">${escapeHtml(resp.description || 'Response')}</span>
                            ${content ? `<span class="schema-type">${escapeHtml(schemaType)}</span>` : ''}
                        </summary>
                        <div class="response-schema-content">
                            ${example != null
                                ? renderCodeBlock(`${code} response`, JSON.stringify(example, null, 2), 'json')
                                : '<p class="empty-inline">No response example provided.</p>'}
                        </div>
                    </details>
                `;
            }).join('')}
        </div>
    `;
}

function exampleValue(prop) {
    if (prop?.example != null) return prop.example;
    if (prop?.default != null) return prop.default;
    if (prop?.type === 'number' || prop?.type === 'integer') return 0;
    if (prop?.type === 'boolean') return false;
    if (prop?.type === 'array') return [];
    if (prop?.type === 'object') return {};
    return prop?.format === 'binary' ? '<file>' : 'string';
}

function requestExample(props) {
    return Object.fromEntries(Object.entries(props || {})
        .filter(([, prop]) => !isFileProperty(prop))
        .map(([name, prop]) => [name, exampleValue(prop)]));
}

function buildCodeExamples(method, path, hasAuth, props, hasFiles, contentType) {
    const upperMethod = method.toUpperCase();
    const baseUrl = apiBaseUrl();
    const url = `${String(baseUrl).replace(/\/$/, '')}${path}`;
    const example = requestExample(props);
    const jsonBody = JSON.stringify(example, null, 2);
    const authCurl = hasAuth ? ` \\\n  -H "Authorization: Bearer <token>"` : '';
    const bodyCurl = hasFiles
        ? Object.entries(props || {}).map(([name, prop]) => isFileProperty(prop)
            ? ` \\\n  -F "${name}=@path/to/file"`
            : ` \\\n  -F "${name}=${exampleValue(prop)}"`).join('')
        : (contentType && Object.keys(example).length ? ` \\\n  -H "Content-Type: application/json" \\\n  -d '${JSON.stringify(example)}'` : '');
    const curl = `curl -X ${upperMethod} "${url}"${authCurl}${bodyCurl}`;

    if (hasFiles) {
        const fileEntries = Object.entries(props || {}).filter(([, prop]) => isFileProperty(prop));
        const textEntries = Object.entries(props || {}).filter(([, prop]) => !isFileProperty(prop));
        const jsForm = [
            ...fileEntries.map(([name, prop]) => isMultiFileProperty(prop)
                ? `for (const file of fileInput.files) formData.append('${name}', file);`
                : `formData.append('${name}', fileInput.files[0]);`),
            ...textEntries.map(([name, prop]) => `formData.append('${name}', '${exampleValue(prop)}');`)
        ].join('\n');
        const javascript = `const formData = new FormData();\n${jsForm}\n\nconst response = await fetch('${url}', {\n  method: '${upperMethod}',${hasAuth ? `\n  headers: { 'Authorization': 'Bearer <token>' },` : ''}\n  body: formData\n});\n\nconst data = await response.json();`;

        const pythonFiles = fileEntries.map(([name]) => `        ("${name}", open("path/to/file.jpg", "rb"))`).join(',\n');
        const pythonData = textEntries.map(([name, prop]) => `"${name}": "${exampleValue(prop)}"`).join(', ');
        const python = `import requests\n\nfiles = [\n${pythonFiles}\n]\nresponse = requests.${method.toLowerCase()}(\n    "${url}",${hasAuth ? `\n    headers={"Authorization": "Bearer <token>"},` : ''}${textEntries.length ? `\n    data={${pythonData}},` : ''}\n    files=files\n)\nprint(response.json())`;

        const dartFields = textEntries.map(([name, prop]) => `request.fields['${name}'] = '${exampleValue(prop)}';`).join('\n');
        const dartFiles = fileEntries.map(([name]) => `request.files.add(await http.MultipartFile.fromPath('${name}', 'path/to/file.jpg'));`).join('\n');
        const dart = `final request = http.MultipartRequest('${upperMethod}', Uri.parse('${url}'));\n${hasAuth ? "request.headers['Authorization'] = 'Bearer <token>';\n" : ''}${dartFields}${dartFields && dartFiles ? '\n' : ''}${dartFiles}\nfinal response = await request.send();\nprint(await response.stream.bytesToString());`;
        return { curl, javascript, python, dart };
    }

    const jsHeaders = [
        ...(hasAuth ? [`'Authorization': 'Bearer <token>'`] : []),
        ...(!hasFiles && contentType ? [`'Content-Type': 'application/json'`] : [])
    ].join(',\n    ');
    const jsBody = !hasFiles && Object.keys(example).length
        ? `,\n  body: JSON.stringify(${jsonBody.replace(/\n/g, '\n  ')})`
        : '';
    const javascript = `const response = await fetch('${url}', {\n  method: '${upperMethod}',${jsHeaders ? `\n  headers: {\n    ${jsHeaders}\n  }` : ''}${jsBody}\n});\n\nconst data = await response.json();`;

    const pythonHeaders = [
        ...(hasAuth ? [`"Authorization": "Bearer <token>"`] : []),
        ...(!hasFiles && contentType ? [`"Content-Type": "application/json"`] : [])
    ].join(', ');
    const python = `import requests\n\nresponse = requests.${method.toLowerCase()}(\n    "${url}"${pythonHeaders ? `,\n    headers={${pythonHeaders}}` : ''}${!hasFiles && Object.keys(example).length ? `,\n    json=${JSON.stringify(example)}` : ''}\n)\nprint(response.json())`;

    const dartHeaders = [
        ...(hasAuth ? [`'Authorization': 'Bearer <token>'`] : []),
        ...(!hasFiles && contentType ? [`'Content-Type': 'application/json'`] : [])
    ].join(', ');
    const dartMethod = ['get', 'post', 'put', 'patch', 'delete'].includes(method.toLowerCase())
        ? method.toLowerCase() : 'send';
    const dart = `final uri = Uri.parse('${url}');\nfinal response = await http.${dartMethod}(\n  uri,${dartHeaders ? `\n  headers: {${dartHeaders}},` : ''}${!hasFiles && Object.keys(example).length ? `\n  body: jsonEncode(${JSON.stringify(example)}),` : ''}\n);\nprint(response.body);`;
    return { curl, javascript, python, dart };
}

function renderEndpoint(path, method, spec) {
    const key = `${method}-${path}`;
    const { props, required, hasFiles, contentType } = getBodyDefinition(spec);
    const hasAuth = spec.security != null;

    const queryParams = (spec.parameters || []).filter(p => p.in === 'query');
    const headerParams = (spec.parameters || []).filter(p => p.in === 'header');
    const pathParams = (spec.parameters || []).filter(p => p.in === 'path');

    // Also detect path parameters from the URL string if not explicitly defined in spec
    const urlPathParams = (path.match(/:[a-zA-Z0-9]+/g) || []).map(p => ({
        name: p.substring(1),
        in: 'path',
        schema: { type: 'string' }
    }));

    // Merge detected path params with specified ones
    const finalPathParams = [...pathParams];
    for (const up of urlPathParams) {
        if (!finalPathParams.some(p => p.name === up.name)) {
            up.required = true;
            finalPathParams.push(up);
        }
    }

    const hasParameters = finalPathParams.length + queryParams.length + headerParams.length > 0;
    const hasBody = props && Object.keys(props).length > 0;
    const defaultTab = hasParameters ? 'parameters' : (hasBody ? 'request' : 'response');
    const activeTab = activeEndpointTabs[key] || defaultTab;
    activeEndpointTabs[key] = activeTab;
    const examples = buildCodeExamples(method, path, hasAuth, props, hasFiles, contentType);
    const activeLanguage = activeExampleLanguages[key] || 'curl';
    const serverUrl = apiBaseUrl();
    const isMutation = !['GET', 'HEAD', 'OPTIONS'].includes(method.toUpperCase());
    const requestBlocked = selectedApiServer().readOnly && isMutation;

    const propsJson = props ? JSON.stringify(props).replace(/"/g, '&quot;') : 'null';
    const hasFilesStr = hasFiles ? 'true' : 'false';

    return `
        <section class="api-section" id="${method.toUpperCase()}-${path}">
            <header class="endpoint-summary">
                <div class="endpoint-header">
                    <span class="method-tag ${method.toUpperCase()}">${method.toUpperCase()}</span>
                    <span class="path-text">${escapeHtml(path)}</span>
                    ${hasAuth ? '<span class="auth-badge"><span class="auth-lock"></span>Authentication required</span>' : '<span class="public-badge">Public</span>'}
                </div>
                <p class="api-description">${escapeHtml(spec.summary || spec.description || 'No description provided')}</p>
                <div class="endpoint-meta">
                    <span><strong>Base URL</strong><code>${escapeHtml(serverUrl)}</code></span>
                    <span><strong>API version</strong><code>${escapeHtml(apiData?.info?.version || 'Not specified')}</code></span>
                </div>
            </header>

            <div class="endpoint-tabs" role="tablist" aria-label="Endpoint documentation">
                <button class="endpoint-tab ${activeTab === 'parameters' ? 'is-active' : ''}" type="button" role="tab"
                    data-endpoint-key="${escapeHtml(key)}" data-tab="parameters" aria-selected="${activeTab === 'parameters'}"
                    onclick="selectEndpointTab('${key}', 'parameters')">Parameters${hasParameters ? `<span>${finalPathParams.length + queryParams.length + headerParams.length}</span>` : ''}</button>
                <button class="endpoint-tab ${activeTab === 'request' ? 'is-active' : ''}" type="button" role="tab"
                    data-endpoint-key="${escapeHtml(key)}" data-tab="request" aria-selected="${activeTab === 'request'}"
                    onclick="selectEndpointTab('${key}', 'request')">Request</button>
                <button class="endpoint-tab ${activeTab === 'response' ? 'is-active' : ''}" type="button" role="tab"
                    data-endpoint-key="${escapeHtml(key)}" data-tab="response" aria-selected="${activeTab === 'response'}"
                    onclick="selectEndpointTab('${key}', 'response')">Response${spec.responses ? `<span>${Object.keys(spec.responses).length}</span>` : ''}</button>
                <button class="endpoint-tab ${activeTab === 'examples' ? 'is-active' : ''}" type="button" role="tab"
                    data-endpoint-key="${escapeHtml(key)}" data-tab="examples" aria-selected="${activeTab === 'examples'}"
                    onclick="selectEndpointTab('${key}', 'examples')">Examples</button>
            </div>

            <div class="endpoint-tab-panel ${activeTab === 'parameters' ? 'is-active' : ''}" role="tabpanel"
                 data-endpoint-key="${escapeHtml(key)}" data-panel="parameters">
                ${hasParameters ? `
                    ${renderParameterGroup(key, 'Path parameters', finalPathParams, 'path')}
                    ${renderParameterGroup(key, 'Query parameters', queryParams, 'query')}
                    ${renderParameterGroup(key, 'Request headers', headerParams, 'header')}
                ` : '<p class="empty-inline panel-empty">This endpoint has no path, query, or custom header parameters.</p>'}
            </div>

            <div class="endpoint-tab-panel ${activeTab === 'request' ? 'is-active' : ''}" role="tabpanel"
                 data-endpoint-key="${escapeHtml(key)}" data-panel="request">
                <div class="request-toolbar">
                    <div>
                        <h3>Request body</h3>
                        <span class="content-type-badge">${escapeHtml(contentType || 'No request body')}</span>
                    </div>
                    <span class="request-requirement">${spec.requestBody?.required ? 'Required' : 'Optional'}</span>
                </div>
                ${hasBody ? `
                    ${!hasFiles ? renderCodeBlock('Body example', JSON.stringify(requestExample(props), null, 2), 'json') : ''}
                    <div class="request-body-form">
                        ${Object.entries(props).map(([name, prop]) => renderFormField(key, name, prop, required.has(name))).join('')}
                    </div>
                ` : '<p class="empty-inline panel-empty">This endpoint does not accept a request body.</p>'}
                <div class="try-panel">
                    <div>
                        <strong>Try this endpoint</strong>
                        <span>Values entered in Parameters and Request will be used.</span>
                    </div>
                    <button class="try-it-out-btn" onclick="executeRequest('${method}', '${path}', ${hasAuth}, ${propsJson}, ${hasFilesStr})" ${loading[key] || requestBlocked ? 'disabled' : ''}>
                        ${requestBlocked ? 'Read-only environment' : (loading[key] ? 'Sending request' : 'Send request')}
                    </button>
                </div>
            </div>

            <div class="endpoint-tab-panel ${activeTab === 'response' ? 'is-active' : ''}" role="tabpanel"
                 data-endpoint-key="${escapeHtml(key)}" data-panel="response">
                ${renderResponseSchemas(spec.responses) || '<p class="empty-inline panel-empty">No documented responses.</p>'}
                ${responses[key] ? `
                    <div class="response-section live-response-card">
                        ${renderResponseMedia(key)}
                        <div class="code-block live-response-block">
                            <div class="code-block-heading">
                                <span>Live response</span>
                                <button type="button" class="code-copy-btn" onclick="copyCode(this)" aria-label="Copy live response">Copy</button>
                            </div>
                            <pre class="response-body">${escapeHtml(responses[key])}</pre>
                        </div>
                    </div>
                ` : ''}
            </div>

            <div class="endpoint-tab-panel ${activeTab === 'examples' ? 'is-active' : ''}" role="tabpanel"
                 data-endpoint-key="${escapeHtml(key)}" data-panel="examples">
                <div class="language-tabs" role="tablist" aria-label="Request code language">
                    ${Object.keys(examples).map(language => `
                        <button type="button" class="language-tab ${activeLanguage === language ? 'is-active' : ''}"
                            data-endpoint-key="${escapeHtml(key)}" data-language="${language}"
                            onclick="selectExampleLanguage('${key}', '${language}')">${language === 'curl' ? 'cURL' : language[0].toUpperCase() + language.slice(1)}</button>
                    `).join('')}
                </div>
                ${Object.entries(examples).map(([language, code]) => `
                    <div class="example-code ${activeLanguage === language ? 'is-active' : ''}"
                         data-endpoint-key="${escapeHtml(key)}" data-example-language="${language}">
                        ${renderCodeBlock(`${language === 'curl' ? 'cURL' : language} request`, code, language)}
                    </div>
                `).join('')}
            </div>
        </section>
    `;
}

function escapeHtml(str) {
    return String(str)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#039;');
}

function collectMediaUrls(value, found = new Set()) {
    if (typeof value === 'string') {
        if (/^(https?:\/\/|\/)/i.test(value) && /\.(avif|gif|jpe?g|png|webp)(\?.*)?$/i.test(value)) {
            found.add(value);
        }
        return [...found];
    }
    if (Array.isArray(value)) {
        value.forEach(item => collectMediaUrls(item, found));
    } else if (value && typeof value === 'object') {
        Object.values(value).forEach(item => collectMediaUrls(item, found));
    }
    return [...found];
}

function renderResponseMedia(key) {
    const media = responseMedia[key] || [];
    if (media.length === 0) return '';
    return `
        <div class="response-media">
            <span class="response-media-label">Uploaded media</span>
            <div class="response-media-grid">
                ${media.map((url, index) => {
                    const resolvedUrl = resolveMediaUrl(url);
                    return `
                    <button
                        type="button"
                        class="response-media-item"
                        data-media-url="${escapeHtml(resolvedUrl)}"
                        onclick="openMediaPreview(this.dataset.mediaUrl)"
                        aria-label="Preview uploaded media ${index + 1}"
                    >
                        <img src="${escapeHtml(resolvedUrl)}" alt="Uploaded media ${index + 1}" loading="lazy">
                    </button>
                `;
                }).join('')}
            </div>
        </div>
    `;
}

function resolveMediaUrl(url) {
    if (/^https?:\/\//i.test(url)) return url;
    return new URL(url, `${apiBaseUrl()}/`).toString();
}

function openMediaPreview(url) {
    const dialog = document.getElementById('mediaPreviewDialog');
    const image = document.getElementById('mediaPreviewImage');
    image.src = url;
    document.getElementById('mediaPreviewCaption').textContent = url;
    if (typeof dialog.showModal === 'function') dialog.showModal();
    else dialog.setAttribute('open', '');
}

function closeMediaPreview() {
    const dialog = document.getElementById('mediaPreviewDialog');
    if (typeof dialog.close === 'function') dialog.close();
    else dialog.removeAttribute('open');
    document.getElementById('mediaPreviewImage').removeAttribute('src');
}

async function copyCode(button) {
    const code = button.closest('.code-block')?.querySelector('pre')?.textContent;
    if (code == null) return;
    try {
        if (navigator.clipboard?.writeText) {
            await navigator.clipboard.writeText(code);
        } else {
            const textarea = document.createElement('textarea');
            textarea.value = code;
            textarea.style.position = 'fixed';
            textarea.style.opacity = '0';
            document.body.appendChild(textarea);
            textarea.select();
            document.execCommand('copy');
            textarea.remove();
        }
        const original = button.textContent;
        button.textContent = 'Copied';
        button.classList.add('is-copied');
        clearTimeout(button._copyTimer);
        button._copyTimer = setTimeout(() => {
            button.textContent = original;
            button.classList.remove('is-copied');
        }, 1400);
    } catch (error) {
        console.error('Unable to copy code:', error);
    }
}

function selectEndpointTab(key, tab) {
    activeEndpointTabs[key] = tab;
    document.querySelectorAll('[data-endpoint-key]').forEach(element => {
        if (element.dataset.endpointKey !== key) return;
        if (element.classList.contains('endpoint-tab')) {
            const selected = element.dataset.tab === tab;
            element.classList.toggle('is-active', selected);
            element.setAttribute('aria-selected', String(selected));
        }
        if (element.classList.contains('endpoint-tab-panel')) {
            element.classList.toggle('is-active', element.dataset.panel === tab);
        }
    });
}

function selectExampleLanguage(key, language) {
    activeExampleLanguages[key] = language;
    document.querySelectorAll('[data-endpoint-key]').forEach(element => {
        if (element.dataset.endpointKey !== key) return;
        if (element.classList.contains('language-tab')) {
            element.classList.toggle('is-active', element.dataset.language === language);
        }
        if (element.classList.contains('example-code')) {
            element.classList.toggle('is-active', element.dataset.exampleLanguage === language);
        }
    });
}

function observeEndpoints() {
    endpointObserver?.disconnect();
    const sections = [...document.querySelectorAll('.api-section')];
    if (!sections.length || typeof IntersectionObserver !== 'function') return;
    endpointObserver = new IntersectionObserver(entries => {
        const visible = entries
            .filter(entry => entry.isIntersecting)
            .sort((a, b) => b.intersectionRatio - a.intersectionRatio)[0];
        if (!visible || visible.target.id === activeEndpointId) return;
        activeEndpointId = visible.target.id;
        document.querySelectorAll('.nav-item').forEach(item => {
            item.classList.toggle('is-active', item.dataset.endpointId === activeEndpointId);
        });
    }, { root: document.querySelector('.main-content'), rootMargin: '-12% 0px -68% 0px', threshold: [0, 0.2, 0.6] });
    sections.forEach(section => endpointObserver.observe(section));
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

function savePathValue(key, field, value) {
    const pKey = `path-${key}`;
    if (!requestBodyValues[pKey]) requestBodyValues[pKey] = {};
    requestBodyValues[pKey][field] = value;
}

async function executeRequest(method, path, hasAuth, props, hasFiles) {
    const key = `${method}-${path}`;
    const server = selectedApiServer();
    const isMutation = !['GET', 'HEAD', 'OPTIONS'].includes(method.toUpperCase());
    if (server.readOnly && isMutation) {
        activeEndpointTabs[key] = 'response';
        responses[key] = `Request blocked: ${server.name} is configured as read-only.`;
        renderApiList();
        return;
    }
    if (isMutation && server.confirmMutations) {
        const confirmed = window.confirm(
            `Send ${method.toUpperCase()} to ${server.name}? This may change production data.`
        );
        if (!confirmed) return;
    }
    const selectedFiles = {};
    if (hasFiles && props) {
        for (const [name, prop] of Object.entries(props)) {
            if (!isFileProperty(prop)) continue;
            const input = document.getElementById(`file-${key}-${name}`);
            selectedFiles[name] = input?.files ? Array.from(input.files) : [];
        }
    }
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

        // Build URL with path and query params
        let url = `${apiBaseUrl()}${path}`;

        // Replace path parameters (:id, etc)
        const savedPathValues = requestBodyValues[`path-${key}`] || {};
        for (const [name, val] of Object.entries(savedPathValues)) {
            if (val) {
                const encoded = encodeURIComponent(val);
                url = url.replace(`{${name}}`, encoded).replace(`:${name}`, encoded);
            }
        }

        const savedQuery = requestBodyValues[`query-${key}`] || {};
        const queryParts = Object.entries(savedQuery).filter(([, v]) => v);
        if (queryParts.length > 0) {
            url += '?' + queryParts.map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`).join('&');
        }

        let resp;
        let responseText;

        if (hasFiles && props) {
            // Multipart: use FormData to carry both text fields and file inputs
            const formData = new FormData();
            for (const [name, prop] of Object.entries(props)) {
                if (isFileProperty(prop)) {
                    for (const file of selectedFiles[name] || []) {
                        if (file.size > MAX_FILE_BYTES) {
                            throw new Error(`File ${file.name} exceeds the 25 MB limit`);
                        }
                        formData.append(name, file);
                    }
                } else {
                    const val = (requestBodyValues[key] || {})[name] || prop.default || '';
                    if (val) formData.append(name, val);
                }
            }
            ({ response: resp, text: responseText } = await fetchTextWithTimeout(
                url,
                { method, headers, body: formData }
            ));
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
            ({ response: resp, text: responseText } = await fetchTextWithTimeout(
                url,
                { method, headers, body }
            ));
        }

        try {
            const json = JSON.parse(responseText);
            responseMedia[key] = resp.ok ? collectMediaUrls(json) : [];
            responseText = JSON.stringify(json, null, 2);
        } catch {
            responseMedia[key] = [];
            // responseText already contains the raw text
        }

        responses[key] = resp.ok ? responseText : `Error ${resp.status}: ${responseText}`;
    } catch (e) {
        responseMedia[key] = [];
        responses[key] = `Error: ${e.message}`;
    }

    loading[key] = false;
    activeEndpointTabs[key] = 'response';
    renderApiList();
    observeEndpoints();
}

document.getElementById('searchInput').addEventListener('input', (e) => {
    searchQuery = e.target.value;
    render();
});

document.getElementById('environmentSelect').addEventListener('change', (event) => {
    selectApiEnvironment(event.target.value);
});

document.getElementById('authInput').addEventListener('input', (e) => {
    authHeader = e.target.value;
    setTokenSaveStatus('Unsaved changes');
});

document.getElementById('saveTokenButton').addEventListener('click', saveAuthorizationToken);

document.getElementById('themeToggle').addEventListener('click', () => {
    isDark = !isDark;
    document.documentElement.setAttribute('data-theme', isDark ? 'dark' : 'light');
    updateThemeToggle();
});

document.getElementById('sidebarToggle').addEventListener('click', () => {
    isSidebarCollapsed = !isSidebarCollapsed;
    updateSidebarState();
});

document.getElementById('settingsToggle').addEventListener('click', () => {
    if (isSidebarCollapsed) isSidebarCollapsed = false;
    updateSidebarState();
    if (currentView !== 'settings') {
        history.pushState({ froggyView: 'settings' }, '', '#settings');
        showView('settings');
    }
});

document.getElementById('settingsBackButton').addEventListener('click', () => {
    if (history.state?.froggyView === 'settings') {
        history.back();
    } else {
        history.replaceState({ froggyView: 'docs' }, '', `${location.pathname}${location.search}`);
        showView('docs');
    }
});

document.getElementById('tokenVisibilityToggle').addEventListener('click', () => {
    isTokenVisible = !isTokenVisible;
    updateTokenVisibility();
});

document.getElementById('mediaPreviewClose').addEventListener('click', closeMediaPreview);
document.getElementById('mediaPreviewDialog').addEventListener('click', (event) => {
    if (event.target === event.currentTarget) closeMediaPreview();
});

document.getElementById('navList').addEventListener('click', (event) => {
    const item = event.target.closest('.nav-item');
    if (item) {
        activeEndpointId = item.dataset.endpointId || '';
        document.querySelectorAll('.nav-item').forEach(navItem => {
            navItem.classList.toggle('is-active', navItem === item);
        });
        showView('docs');
    }
});

window.addEventListener('popstate', () => {
    showView(location.hash === '#settings' ? 'settings' : 'docs');
});

document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && currentView === 'settings') {
        document.getElementById('settingsBackButton').click();
    }
});

function updateThemeToggle() {
    const toggle = document.getElementById('themeToggle');
    toggle.setAttribute('aria-label', isDark ? 'Switch to light mode' : 'Switch to dark mode');
    toggle.title = isDark ? 'Switch to light mode' : 'Switch to dark mode';
    document.getElementById('themeModeLabel').textContent = isDark ? 'Dark mode' : 'Light mode';
}

function updateSidebarState() {
    const app = document.getElementById('appContainer');
    const sidebarToggle = document.getElementById('sidebarToggle');

    app.classList.toggle('sidebar-collapsed', isSidebarCollapsed);
    sidebarToggle.setAttribute('aria-label', isSidebarCollapsed ? 'Expand sidebar' : 'Collapse sidebar');
    sidebarToggle.title = isSidebarCollapsed ? 'Expand sidebar' : 'Collapse sidebar';
}

function showView(view) {
    currentView = view;
    document.getElementById('docsView').hidden = view !== 'docs';
    document.getElementById('settingsView').hidden = view !== 'settings';
    document.getElementById('settingsToggle').classList.toggle('is-active', view === 'settings');
    document.querySelector('.main-content').scrollTop = 0;
}

function updateTokenVisibility() {
    const input = document.getElementById('authInput');
    const toggle = document.getElementById('tokenVisibilityToggle');
    input.type = isTokenVisible ? 'text' : 'password';
    toggle.classList.toggle('is-visible', isTokenVisible);
    toggle.setAttribute('aria-label', isTokenVisible ? 'Hide token' : 'Show token');
    toggle.title = isTokenVisible ? 'Hide token' : 'Show token';
}

function setTokenSaveStatus(message, isError = false) {
    const status = document.getElementById('tokenSaveStatus');
    status.textContent = message;
    status.classList.toggle('is-error', isError);
}

async function saveAuthorizationToken() {
    const button = document.getElementById('saveTokenButton');
    const input = document.getElementById('authInput');
    const token = authHeader.trim();
    button.disabled = true;
    button.textContent = 'Saving';

    try {
        await window.froggyTokenStorage.save(token);
        authHeader = token;
        input.value = token;
        setTokenSaveStatus(token ? 'Token saved securely' : 'Saved token removed');
    } catch (error) {
        console.error('Unable to save authorization token:', error);
        setTokenSaveStatus('Encrypted storage is unavailable', true);
    } finally {
        button.disabled = false;
        button.textContent = 'Save token';
    }
}

async function loadSavedAuthorizationToken() {
    try {
        const token = await window.froggyTokenStorage.load();
        if (token) {
            authHeader = token;
            document.getElementById('authInput').value = token;
            setTokenSaveStatus('Saved token restored');
        }
    } catch (error) {
        console.error('Unable to restore authorization token:', error);
        setTokenSaveStatus('Unable to restore the saved token', true);
    }
}

document.documentElement.setAttribute('data-theme', 'light');
updateThemeToggle();
updateSidebarState();
updateTokenVisibility();
showView(location.hash === '#settings' ? 'settings' : 'docs');
loadSavedAuthorizationToken();

loadData();
setInterval(loadData, 3000);
