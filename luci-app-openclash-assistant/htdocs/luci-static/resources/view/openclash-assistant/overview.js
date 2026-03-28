'use strict';
'require view';
'require form';
'require fs';
'require ui';

function safeParse(text, fallback) {
	try {
		return JSON.parse(text);
	} catch (error) {
		return fallback;
	}
}

function execAssistantJson(action, fallback) {
	return fs.exec('/usr/libexec/openclash-assistant/diag.sh', [ action ]).then(function(res) {
		return safeParse((res && res.stdout) || '{}', fallback || {});
	}).catch(function() {
		return fallback || {};
	});
}

function readCachedJson(key, fallback) {
	try {
		var text = window.localStorage.getItem(key);
		if (!text)
			return fallback;
		return safeParse(text, fallback);
	} catch (error) {
		return fallback;
	}
}

function writeCachedJson(key, value) {
	try {
		window.localStorage.setItem(key, JSON.stringify(value || {}));
	} catch (error) {}
}

function withTimeout(promise, timeoutMs, fallback) {
	return new Promise(function(resolve) {
		var settled = false;
		var timer = window.setTimeout(function() {
			if (settled)
				return;
			settled = true;
			resolve(fallback);
		}, timeoutMs || 1500);

		promise.then(function(result) {
			if (settled)
				return;
			settled = true;
			window.clearTimeout(timer);
			resolve(result);
		}).catch(function() {
			if (settled)
				return;
			settled = true;
			window.clearTimeout(timer);
			resolve(fallback);
		});
	});
}

function yesNo(value) {
	return value ? '是' : '否';
}

function preBlock(text) {
	return E('pre', { 'class': 'oca-pre' }, text || '-');
}

function zhRisk(value) {
	if (value === 'low')
		return '低';
	if (value === 'medium')
		return '中';
	if (value === 'high')
		return '高';
	return value || '未知';
}

function riskTone(value) {
	var mapped = zhRisk(value);
	if (mapped === '低')
		return 'good';
	if (mapped === '高')
		return 'bad';
	return 'warn';
}

function badge(label, tone) {
	return E('span', {
		'class': 'oca-badge oca-badge-' + (tone || 'neutral')
	}, label);
}

function actionButton(label, onClick, tone) {
	return E('button', {
		'class': 'btn cbi-button cbi-button-apply oca-action' + (tone ? (' oca-action-' + tone) : ''),
		'click': function(ev) {
			ev.preventDefault();
			onClick();
		}
	}, [ label ]);
}

function toneColor(tone) {
	if (tone === 'good')
		return '#16a34a';
	if (tone === 'bad')
		return '#dc2626';
	return '#d97706';
}

function routeFitTone(value) {
	if (value === 'yes')
		return 'good';
	if (value === 'no')
		return 'bad';
	return 'warn';
}

function routeFitLabel(value) {
	if (value === 'yes')
		return '走向合理';
	if (value === 'no')
		return '走向不符';
	return '待补充判断';
}

function routeKindLabel(value) {
	if (value === 'direct')
		return '更像直连';
	if (value === 'proxy')
		return '更像代理';
	if (value === 'blocked')
		return '疑似被拦截';
	return '暂未识别';
}

function isAiMediaTarget(key) {
	return [ 'openai', 'claude', 'gemini', 'grok', 'perplexity', 'poe', 'cursor', 'codex' ].indexOf(key) >= 0;
}

function aiServicePurpose(key) {
	if (key === 'openai')
		return '更偏对话和 API';
	if (key === 'claude')
		return '更偏长文本和分析';
	if (key === 'gemini')
		return '更偏谷歌生态和搜索整合';
	if (key === 'grok')
		return '更偏实时信息和 X 生态';
	if (key === 'perplexity')
		return '更偏搜索问答';
	if (key === 'poe')
		return '更偏多模型聚合';
	if (key === 'cursor' || key === 'codex')
		return '更偏写代码和开发工具';
	return 'AI 服务';
}

function aiServiceAdvice(key, mediaAi) {
	var status = mediaAi[key + '_status'] || 'no_data';
	var httpCode = String(mediaAi[key + '_http_code'] || '');

	if ((key === 'openai' || key === 'codex') && httpCode === '401')
		return '当前链路基本正常，但还缺 API 认证；更像是密钥问题，不一定是节点问题。';
	if (key === 'gemini' && httpCode === '400')
		return '当前链路基本正常，更像是测试用 Key 无效，不一定是线路问题。';
	if (status === 'reachable' || status === 'available' || status === 'full_support')
		return '当前连通性正常，适合继续用作' + aiServicePurpose(key) + '。';
	if (status === 'restricted' || status === 'blocked')
		return '当前更像地区或策略受限，建议优先换到 AI 分组或国际稳定节点。';
	if (status === 'failed')
		return '当前连通性不稳定，建议先检查 DNS，再换到延迟更低、地区更合适的节点。';
	return '还没有拿到稳定结果，建议跑一次真实检测再判断。';
}

function aiServiceRegionHint(key) {
	if (key === 'openai' || key === 'codex' || key === 'claude' || key === 'cursor')
		return '优先尝试美国 / 新加坡 / 日本等更常见的 AI 节点。';
	if (key === 'gemini' || key === 'perplexity')
		return '优先尝试美国 / 日本 / 新加坡，并尽量保持 DNS 和节点地区一致。';
	if (key === 'grok' || key === 'poe')
		return '优先尝试美国或稳定国际节点，避免地区频繁跳变。';
	return '优先尝试稳定的国际节点。';
}

function streamingServiceAdvice(key, mediaAi) {
	var status = mediaAi[key + '_status'] || 'no_data';

	if (status === 'reachable' || status === 'available' || status === 'full_support')
		return '当前可以访问，适合继续观察延迟和稳定性，再决定要不要长期作为主力节点。';
	if (status === 'other_region' || status === 'homemade_only')
		return '当前能用但地区不太理想，更适合继续换到更匹配的地区节点。';
	if (status === 'restricted' || status === 'no_unlock' || status === 'blocked')
		return '当前更像地区限制或策略不合适，建议优先换流媒体分组或对应地区节点。';
	if (status === 'failed')
		return '当前检测失败，更像线路质量、TLS 或 DNS 问题，建议先做 DNS 和节点排查。';
	return '还没有拿到稳定结果，建议先跑一次真实检测。';
}

function streamingLongTermLabel(key, mediaAi) {
	var status = mediaAi[key + '_status'] || 'no_data';

	if (status === 'reachable' || status === 'available' || status === 'full_support')
		return '可作为候选主力';
	if (status === 'other_region' || status === 'homemade_only')
		return '可临时使用';
	if (status === 'restricted' || status === 'no_unlock' || status === 'blocked' || status === 'failed')
		return '不建议长期使用';
	return '等待检测';
}

function browserVisibleBackend(url) {
	if (!url)
		return url;

	try {
		var parsed = new URL(url, window.location.origin);
		if ([ '127.0.0.1', 'localhost', '0.0.0.0' ].indexOf(parsed.hostname) >= 0)
			return parsed.protocol + '//' + window.location.hostname + (parsed.port ? (':' + parsed.port) : '');
		return parsed.origin;
	} catch (error) {
		return url;
	}
}

function buildEmbeddedFrontendUrl(subconvert) {
	var frontendPath = '/luci-static/openclash-assistant/sub-web-modify/index.html';
	var backend = browserVisibleBackend(subconvert.backend_origin || subconvert.backend || 'http://127.0.0.1:25500');
	var params = [ 'backend=' + encodeURIComponent(backend) ];

	if (subconvert.source)
		params.push('url=' + encodeURIComponent(subconvert.source));
	if (subconvert.template_url)
		params.push('config=' + encodeURIComponent(subconvert.template_url));

	params.push('target=clash');
	return frontendPath + '?' + params.join('&');
}

function ensureOverviewTheme() {
	if (document.getElementById('openclash-assistant-theme'))
		return;

	var style = document.createElement('style');
	style.id = 'openclash-assistant-theme';
	style.textContent = [
		'.oca-shell{--oca-bg:#f8fafc;--oca-surface:#ffffff;--oca-surface-soft:#f3f8f7;--oca-line:#d7e3e0;--oca-ink:#102a43;--oca-muted:#5b7083;--oca-accent:#0f766e;--oca-accent-soft:#dff7f3;--oca-warn:#c47a12;--oca-warn-soft:#fff7df;--oca-bad:#c2410c;--oca-bad-soft:#fff1eb;}',
		'.oca-shell{padding:10px 0 22px;}',
		'.oca-shell[data-display-mode="simple"] .oca-advanced-only{display:none !important;}',
		'.oca-shell[data-display-mode="advanced"] .oca-simple-only{display:none !important;}',
		'.oca-shell>h2{margin:0 0 12px;font-size:28px;font-weight:800;letter-spacing:-0.03em;color:var(--oca-ink);}',
		'.oca-shell .cbi-map-descr{margin:0 0 16px;color:var(--oca-muted);font-size:14px;line-height:1.7;}',
		'.oca-hero{display:grid;grid-template-columns:minmax(0,1.5fr) minmax(300px,1fr);gap:14px;margin:6px 0 18px;}',
		'.oca-hero-main,.oca-hero-side{border:1px solid var(--oca-line);border-radius:24px;background:linear-gradient(145deg,#fcfffe 0%,#eef7f6 100%);box-shadow:0 18px 40px rgba(15,23,42,.06);padding:22px 24px;}',
		'.oca-topbar{display:flex;align-items:center;justify-content:space-between;gap:12px;flex-wrap:wrap;margin:0 0 12px;}',
		'.oca-mode-switch{display:flex;align-items:center;gap:6px;padding:6px;border:1px solid var(--oca-line);border-radius:999px;background:rgba(255,255,255,.88);}',
		'.oca-mode-chip{border:0 !important;background:transparent !important;color:#335266 !important;border-radius:999px !important;padding:8px 14px !important;font-weight:800;}',
		'.oca-mode-chip.active{background:linear-gradient(135deg,#0f766e 0%,#115e59 100%) !important;color:#fff !important;box-shadow:0 8px 16px rgba(15,118,110,.16);}',
		'.oca-mode-hint{font-size:12px;color:var(--oca-muted);}',
		'.oca-quick-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:12px;margin:0 0 18px;}',
		'.oca-quick-card{border:1px solid var(--oca-line);border-radius:22px;background:linear-gradient(180deg,#fff 0%,#f7fbfa 100%);padding:18px;box-shadow:0 10px 30px rgba(15,23,42,.04);display:flex;flex-direction:column;gap:10px;min-height:176px;}',
		'.oca-quick-kicker{display:inline-flex;align-self:flex-start;padding:4px 10px;border-radius:999px;background:#eef7f6;color:#0f766e;font-size:11px;font-weight:800;letter-spacing:.04em;}',
		'.oca-quick-title{font-size:16px;font-weight:900;color:var(--oca-ink);line-height:1.35;}',
		'.oca-quick-copy{color:var(--oca-muted);font-size:13px;line-height:1.7;min-height:44px;}',
		'.oca-quick-actions{margin-top:auto;}',
		'.oca-assistant-grid{display:grid;grid-template-columns:minmax(0,1.15fr) minmax(300px,.85fr);gap:16px;}',
		'.oca-stack{display:flex;flex-direction:column;gap:16px;}',
		'.oca-summary-card{border:1px solid var(--oca-line);border-radius:22px;background:linear-gradient(145deg,#fff 0%,#eff7f5 100%);padding:18px 20px;box-shadow:0 10px 30px rgba(15,23,42,.04);}',
		'.oca-summary-eyebrow{font-size:12px;font-weight:800;color:#0f766e;letter-spacing:.06em;text-transform:uppercase;}',
		'.oca-summary-title{margin:10px 0 8px;font-size:22px;line-height:1.2;font-weight:900;color:var(--oca-ink);}',
		'.oca-summary-copy{margin:0;color:var(--oca-muted);font-size:14px;line-height:1.8;}',
		'.oca-dual{display:grid;grid-template-columns:minmax(0,1.08fr) minmax(320px,.92fr);gap:16px;align-items:start;}',
		'.oca-kicker{display:inline-flex;align-items:center;gap:8px;padding:6px 12px;border-radius:999px;background:rgba(15,118,110,.1);color:var(--oca-accent);font-size:12px;font-weight:800;letter-spacing:.08em;text-transform:uppercase;}',
		'.oca-hero-title{margin:14px 0 10px;font-size:30px;line-height:1.08;font-weight:900;color:var(--oca-ink);max-width:14em;}',
		'.oca-hero-copy{margin:0;color:var(--oca-muted);font-size:14px;line-height:1.8;max-width:52em;}',
		'.oca-mini-grid,.oca-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:12px;margin-top:12px;}',
		'.oca-mini-grid{grid-template-columns:repeat(2,minmax(0,1fr));margin-top:0;}',
		'.oca-panel{border:1px solid var(--oca-line);border-radius:22px;background:linear-gradient(180deg,#fff 0%,#f7fbfa 100%);box-shadow:0 10px 30px rgba(15,23,42,.04);padding:18px 20px;margin-bottom:16px;}',
		'.oca-panel h3{margin:0 0 12px;font-size:20px;font-weight:800;color:var(--oca-ink);letter-spacing:-0.02em;}',
		'.oca-panel h4{margin:18px 0 8px;font-size:14px;font-weight:800;color:#244a5a;letter-spacing:.01em;}',
		'.oca-table{margin-top:8px;border-radius:14px;overflow:hidden;}',
		'.oca-table td{padding:10px 12px;border-color:#e7efec;}',
		'.oca-table td:first-child{width:200px;color:#486171;font-weight:700;}',
		'.oca-shell .cbi-value-description{margin-top:6px;color:#5b7083;font-size:12px;line-height:1.7;background:#f5faf9;border:1px solid #e1ece8;border-radius:12px;padding:8px 10px;}',
		'.oca-shell .cbi-value-title{font-weight:800;color:#163047;}',
		'.oca-shell .cbi-value{padding-top:14px;padding-bottom:14px;border-color:#e7efec;}',
		'.oca-subtle{margin:10px 0 0;color:var(--oca-muted);font-size:13px;line-height:1.75;}',
		'.oca-subtle.is-warn{color:var(--oca-warn);font-weight:700;}',
		'.oca-scene-list{display:flex;flex-direction:column;gap:10px;margin-top:12px;}',
		'.oca-scene-item{border:1px solid #dbe8e4;border-radius:16px;background:#fff;padding:12px 14px;}',
		'.oca-scene-title{font-size:13px;font-weight:800;color:var(--oca-ink);margin-bottom:4px;}',
		'.oca-scene-copy{font-size:12px;line-height:1.75;color:var(--oca-muted);}',
		'.oca-card{border:1px solid var(--oca-line);border-radius:18px;padding:16px;background:linear-gradient(180deg,#fff 0%,#f5faf9 100%);box-shadow:0 1px 2px rgba(15,23,42,.04);min-height:118px;}',
		'.oca-card.is-hero{background:linear-gradient(180deg,#fff 0%,#eef8f6 100%);}',
		'.oca-card-title{font-size:15px;font-weight:800;color:var(--oca-ink);margin-bottom:8px;}',
		'.oca-card-subtitle{font-size:11px;color:var(--oca-muted);margin-bottom:6px;}',
		'.oca-card-status{font-size:13px;font-weight:800;letter-spacing:.02em;margin-bottom:8px;}',
		'.oca-card-exit{margin-bottom:8px;line-height:1.45;}',
		'.oca-card-value{font-size:32px;line-height:1.05;font-weight:900;color:var(--oca-ink);letter-spacing:-0.04em;}',
		'.oca-card-value.is-compact{font-size:14px;line-height:1.65;font-weight:800;letter-spacing:0;word-break:break-word;}',
		'.oca-card-footer{font-size:11px;color:var(--oca-muted);margin-top:10px;line-height:1.55;}',
		'.oca-card-footer.is-hidden{display:none;}',
		'.oca-card-meta{display:grid;gap:6px;margin-top:10px;}',
		'.oca-badge{display:inline-flex;align-items:center;margin-right:8px;margin-bottom:6px;padding:4px 10px;border-radius:999px;color:#fff;font-size:12px;font-weight:700;box-shadow:inset 0 -1px 0 rgba(255,255,255,.14);}',
		'.oca-badge-good{background:#15803d;}',
		'.oca-badge-warn{background:#b7791f;}',
		'.oca-badge-bad{background:#c2410c;}',
		'.oca-badge-neutral{background:#64748b;}',
		'.oca-callout{margin-bottom:12px;padding:12px 14px;border-radius:14px;border:1px solid;line-height:1.6;font-weight:700;}',
		'.oca-callout-good{background:#f0fdf4;border-color:#bbf7d0;color:#166534;}',
		'.oca-callout-info{background:#eff6ff;border-color:#bfdbfe;color:#1d4ed8;}',
		'.oca-callout-warn{background:#fffbeb;border-color:#fde68a;color:#92400e;}',
		'.oca-frame{margin-top:12px;border:1px solid var(--oca-line);border-radius:20px;overflow:hidden;background:#fff;box-shadow:0 1px 2px rgba(15,23,42,.04);}',
		'.oca-frame iframe{display:block;width:100%;min-height:920px;border:0;background:#fff;}',
		'.oca-tabbar{display:flex;gap:8px;flex-wrap:wrap;margin:18px 0 14px;padding:6px;border:1px solid var(--oca-line);border-radius:18px;background:rgba(255,255,255,.85);backdrop-filter:blur(8px);}',
		'.oca-tab{border-radius:999px !important;padding:8px 14px !important;border:1px solid transparent !important;background:transparent !important;color:#335266 !important;font-weight:700;}',
		'.oca-tab.active{background:linear-gradient(135deg,#0f766e 0%,#115e59 100%) !important;color:#fff !important;border-color:#0f766e !important;box-shadow:0 10px 20px rgba(15,118,110,.18);}',
		'.oca-filterbar{display:flex;flex-wrap:wrap;gap:8px;margin:14px 0 2px;}',
		'.oca-filterbar .oca-action{margin:0;}',
		'.oca-action{margin-top:8px;margin-right:8px;border-radius:999px !important;padding:8px 14px !important;font-weight:700;}',
		'.oca-action-secondary{background:#eff6ff !important;border-color:#bfdbfe !important;color:#1d4ed8 !important;}',
		'.oca-action-ghost{background:#fff !important;border-color:#d7e3e0 !important;color:#335266 !important;}',
		'.oca-checkup-list{display:flex;flex-direction:column;gap:12px;margin-top:12px;}',
		'.oca-checkup-item{border:1px solid var(--oca-line);border-radius:18px;background:linear-gradient(180deg,#fff 0%,#f7fbfa 100%);padding:16px 16px 14px;box-shadow:0 1px 2px rgba(15,23,42,.04);}',
		'.oca-checkup-head{display:flex;align-items:flex-start;justify-content:space-between;gap:12px;margin-bottom:8px;}',
		'.oca-checkup-title{font-size:15px;font-weight:900;color:var(--oca-ink);}',
		'.oca-checkup-text{font-size:13px;line-height:1.75;color:var(--oca-muted);}',
		'.oca-checkup-next{margin-top:8px;font-size:12px;line-height:1.7;color:#244a5a;font-weight:700;}',
		'.oca-link-list{display:flex;flex-direction:column;gap:8px;margin-top:12px;}',
		'.oca-link-item{display:flex;align-items:flex-start;justify-content:space-between;gap:10px;padding:10px 12px;border:1px solid #dbe8e4;border-radius:14px;background:#fff;}',
		'.oca-link-title{font-size:13px;font-weight:800;color:var(--oca-ink);}',
		'.oca-link-copy{font-size:12px;color:var(--oca-muted);line-height:1.65;}',
		'.oca-recommend-list{display:flex;flex-direction:column;gap:10px;margin-top:12px;}',
		'.oca-recommend-item{border:1px solid #dbe8e4;border-radius:16px;background:#fff;padding:12px 14px;}',
		'.oca-recommend-title{font-size:13px;font-weight:800;color:var(--oca-ink);margin-bottom:4px;}',
		'.oca-recommend-value{font-size:14px;line-height:1.7;color:#163047;font-weight:700;}',
		'.oca-recommend-note{margin-top:4px;font-size:12px;line-height:1.7;color:var(--oca-muted);}',
		'.oca-route-form{display:grid;grid-template-columns:minmax(0,1fr) auto;gap:10px;align-items:end;margin:14px 0 10px;}',
		'.oca-route-field{display:flex;flex-direction:column;gap:6px;}',
		'.oca-route-label{font-size:12px;font-weight:800;color:#244a5a;}',
		'.oca-route-input{width:100%;min-height:46px;padding:11px 14px;border:1px solid #d7e3e0;border-radius:14px;background:#fff;color:var(--oca-ink);box-shadow:inset 0 1px 2px rgba(15,23,42,.03);}',
		'.oca-route-input:focus{outline:none;border-color:#0f766e;box-shadow:0 0 0 3px rgba(15,118,110,.12);}',
		'.oca-preset-bar{display:flex;flex-wrap:wrap;gap:8px;margin:8px 0 2px;}',
		'.oca-preset{margin:0 !important;border-radius:999px !important;padding:7px 12px !important;background:#fff !important;border-color:#d7e3e0 !important;color:#335266 !important;font-weight:700;}',
		'.oca-route-result{margin-top:14px;}',
		'.oca-pre{white-space:pre-wrap;word-break:break-all;background:#f4f7f8;padding:12px 14px;border-radius:14px;border:1px solid #dde8e5;color:#29404e;}',
		'@media (max-width:960px){.oca-hero,.oca-assistant-grid,.oca-dual{grid-template-columns:1fr;}.oca-mini-grid{grid-template-columns:1fr 1fr;}.oca-shell>h2{font-size:24px;}.oca-hero-title{font-size:24px;}}',
		'@media (max-width:640px){.oca-mini-grid{grid-template-columns:1fr;}.oca-panel{padding:16px;}.oca-tabbar{padding:4px;}.oca-tab{width:100%;justify-content:center;}.oca-route-form{grid-template-columns:1fr;}}'
	].join('');
	document.head.appendChild(style);
}

function callout(text, tone) {
	return E('div', { 'class': 'oca-callout oca-callout-' + (tone || 'info') }, text);
}

function subtleText(text, isWarn) {
	return E('p', { 'class': 'oca-subtle' + (isWarn ? ' is-warn' : '') }, text);
}

function dataTable(rows) {
	return E('table', { 'class': 'table cbi-section-table oca-table' }, rows);
}

function setBadgeNode(node, label, tone) {
	if (!node)
		return;

	node.textContent = label || '-';
	node.className = 'oca-badge oca-badge-' + (tone || 'neutral');
}

function setInfoCardContent(card, value, footer) {
	if (!card)
		return;

	var valueNode = card.querySelector('.oca-card-value');
	var footerNode = card.querySelector('.oca-card-footer');

	if (valueNode)
		valueNode.textContent = value || '-';
	if (footerNode)
		footerNode.textContent = footer || '-';
}

function updateStatusCardNodes(status) {
	Array.prototype.forEach.call(document.querySelectorAll('[data-status-badge]'), function(node) {
		var key = node.getAttribute('data-status-badge');

		if (key === 'running')
			setBadgeNode(node, status.running ? 'OpenClash 正在运行' : 'OpenClash 未运行', status.running ? 'good' : 'bad');
		else if (key === 'dns')
			setBadgeNode(node, status.dns_diag_level === 'good' ? '解析基本正常' : '解析需要关注', status.dns_diag_level === 'good' ? 'good' : 'warn');
		else if (key === 'auto')
			setBadgeNode(node, status.stream_auto_select === '1' ? '已开启自动切换' : '未开启自动切换', status.stream_auto_select === '1' ? 'good' : 'warn');
	});

	Array.prototype.forEach.call(document.querySelectorAll('[data-status-card]'), function(card) {
		var key = card.getAttribute('data-status-card');

		if (key === 'running')
			setInfoCardContent(card, status.running ? '正常' : '未启动', status.dns_diag_summary || '-');
		else if (key === 'role')
			setInfoCardContent(card, simpleRoleLabel(status.routing_role), '来自当前基础场景配置');
		else if (key === 'mode')
			setInfoCardContent(card, simpleModeLabel(status.preferred_mode), '当前建议会参考这个偏好');
		else if (key === 'node')
			setInfoCardContent(card, status.current_node || '暂未识别', status.current_node_delay ? ('最近延迟 ' + status.current_node_delay + ' ms') : '还没有拿到节点延迟');
		else if (key === 'exit')
			setInfoCardContent(card, (status.exit_country || '-') + (status.exit_colo ? (' / ' + status.exit_colo) : ''), status.exit_ip || '暂未识别出口 IP');
		else if (key === 'resources')
			setInfoCardContent(card, (status.cpu_pct || '-') + '% / ' + (status.mem_pct || '-') + '%', status.clash_mem_mb ? ('Clash 内存 ' + status.clash_mem_mb + ' MB') : '系统 CPU / 内存占用');
		else if (key === 'config')
			setInfoCardContent(card, status.config_name || String(status.config_count || 0), status.config_updated_at ? ('最近更新 ' + status.config_updated_at) : (status.openclash_config ? '已检测到 OpenClash 配置文件' : '还没有检测到 OpenClash 配置文件'));
	});

	Array.prototype.forEach.call(document.querySelectorAll('[data-hero-status-card]'), function(card) {
		var key = card.getAttribute('data-hero-status-card');

		if (key === 'openclash')
			setInfoCardContent(card, status.running ? '运行中' : '未运行', status.dns_diag_summary || '等待检测');
		else if (key === 'node')
			setInfoCardContent(card, status.current_node || '暂未识别', status.current_node_delay ? ('延迟 ' + status.current_node_delay + ' ms') : '等待采集');
		else if (key === 'exit')
			setInfoCardContent(card, status.exit_country || '-', status.exit_ip || '等待采集');
	});

	Array.prototype.forEach.call(document.querySelectorAll('[data-live-card]'), function(card) {
		var key = card.getAttribute('data-live-card');

		if (key === 'hero-openclash')
			setInfoCardContent(card, status.running ? '运行中' : '未运行', status.dns_diag_summary || '等待检测');
		else if (key === 'hero-current-node')
			setInfoCardContent(card, status.current_node || '暂未识别', status.current_node_delay ? ('延迟 ' + status.current_node_delay + ' ms') : '等待采集');
		else if (key === 'hero-exit')
			setInfoCardContent(card, status.exit_country || '-', status.exit_ip || '等待采集');
	});
}

function updateSubconvertCardNodes(subconvert) {
	Array.prototype.forEach.call(document.querySelectorAll('[data-subconvert-badge]'), function(node) {
		var key = node.getAttribute('data-subconvert-badge');

		if (key === 'source')
			setBadgeNode(node, subconvert.source ? '已填写原始订阅' : '等待填写订阅', subconvert.source ? 'good' : 'warn');
		else if (key === 'template')
			setBadgeNode(node, subconvert.template_name || '模板待确认', subconvert.template_name ? 'good' : 'warn');
		else if (key === 'backend')
			setBadgeNode(node, subconvert.backend_ready ? '转换后端正常' : '转换后端待检查', subconvert.backend_ready ? 'good' : 'warn');
	});

	Array.prototype.forEach.call(document.querySelectorAll('[data-subconvert-card]'), function(card) {
		var key = card.getAttribute('data-subconvert-card');

		if (key === 'source')
			setInfoCardContent(card, subconvert.source ? (subconvert.source_valid ? '已填写' : '格式异常') : '待填写', subconvert.source_status_text || '先填写原始订阅地址。');
		else if (key === 'template')
			setInfoCardContent(card, subconvert.template_name || '未设置', subconvert.template_status_text || '先确认模板是否匹配。');
		else if (key === 'backend')
			setInfoCardContent(card, subconvert.backend_ready ? '已连通' : '待确认', subconvert.backend_status_text || '默认建议保持当前转换后端。');
		else if (key === 'groups')
			setInfoCardContent(card, subconvert.expected_groups_text || '国内直连、国际常用、AI、流媒体', subconvert.expected_ai || 'AI 服务建议单独走 AI 或国际稳定分组。');
	});

	Array.prototype.forEach.call(document.querySelectorAll('[data-hero-subconvert-card]'), function(card) {
		setInfoCardContent(card, subconvert.template_name || '未设置', subconvert.source ? '已填写原始订阅' : '等待导入订阅');
	});

	Array.prototype.forEach.call(document.querySelectorAll('[data-live-card="hero-subconvert"]'), function(card) {
		setInfoCardContent(card, subconvert.template_name || '未设置', subconvert.source ? '已填写原始订阅' : '等待导入订阅');
	});

	Array.prototype.forEach.call(document.querySelectorAll('[data-subconvert-next-step]'), function(node) {
		node.textContent = subconvert.next_step || '在这个页面完成原始订阅填写、转换预览和一键导入。';
	});

	Array.prototype.forEach.call(document.querySelectorAll('[data-subconvert-copy="convert"]'), function(node) {
		node.textContent = subconvert.should_convert_text || '建议先转换再导入。';
	});

	Array.prototype.forEach.call(document.querySelectorAll('[data-subconvert-copy="template"]'), function(node) {
		node.textContent = (subconvert.recommended_template_name || '未匹配') + '。如果你不确定，优先用推荐模板。';
	});

	Array.prototype.forEach.call(document.querySelectorAll('[data-subconvert-copy="flow"]'), function(node) {
		node.textContent = subconvert.expected_domestic || '国内默认直连，国际、AI、流媒体按分组处理。';
	});
}

function describeOption(option, text) {
	option.description = text;
	return option;
}

function infoCard(options) {
	var attrs = options.attrs || {};
	attrs['class'] = ((attrs['class'] || '') + ' oca-card' + (options.hero ? ' is-hero' : '')).trim();

	var children = [ E('div', { 'class': 'oca-card-title' }, options.title || '') ];

	if (options.subtitle)
		children.push(E('div', { 'class': 'oca-card-subtitle' }, options.subtitle));
	if (options.status)
		children.push(E('div', { 'class': 'oca-card-status', 'data-field': 'status', 'style': options.statusColor ? ('color:' + options.statusColor + ';') : '' }, options.status));
	if (options.exit)
		children.push(E('div', { 'class': 'oca-card-exit', 'data-field': 'exit', 'style': options.exitStyle || '' }, options.exit));
	if (options.value)
		children.push(E('div', { 'class': 'oca-card-value' + (options.valueClass ? (' ' + options.valueClass) : ''), 'data-field': options.valueField || 'latency' }, options.value));
	if (options.footer)
		children.push(E('div', { 'class': 'oca-card-footer' + (options.footerHidden ? ' is-hidden' : ''), 'data-field': options.footerField || 'http' }, options.footer));
	if (options.extraNode)
		children.push(options.extraNode);

	return E('div', attrs, children);
}

function setActiveTab(tabBar, tabContent, activeKey) {
	Array.prototype.forEach.call(tabContent.children, function(pane) {
		pane.style.display = pane.getAttribute('data-tab-pane') === activeKey ? '' : 'none';
	});

	Array.prototype.forEach.call(tabBar.children, function(btn) {
		if (btn.getAttribute('data-tab-key') === activeKey)
			btn.classList.add('active');
		else
			btn.classList.remove('active');
	});
}

function updateAccessCardNodes(mediaAi) {
	Array.prototype.forEach.call(document.querySelectorAll('[data-media-card]'), function(card) {
		var key = card.getAttribute('data-media-card');
		var statusNode = card.querySelector('[data-field="status"]');
		var latencyNode = card.querySelector('[data-field="latency"]');
		var httpNode = card.querySelector('[data-field="http"]');
		var subtitleNode = card.querySelector('.oca-card-subtitle');
		var exitNode = card.querySelector('[data-field="exit"]');
		var diagnosisNode = card.querySelector('[data-field="diagnosis"]');
		var riskNode = card.querySelector('[data-field="risk"]');
		var nextNode = card.querySelector('[data-field="next"]');
		var tone = mediaAi[key + '_tone'] || 'warn';
		var footer = 'DNS ' + (mediaAi[key + '_dns_state'] || '未检测')
			+ ' · TLS ' + (mediaAi[key + '_tls_state'] || '未检测')
			+ ' · ' + (mediaAi[key + '_http_state'] || ('HTTP ' + (mediaAi[key + '_http_code'] || '-')));

		if (statusNode) {
			statusNode.textContent = mediaAi[key + '_status_text'] || '暂无结果';
			statusNode.style.color = toneColor(tone);
		}
		card.setAttribute('data-media-status', mediaAi[key + '_status'] || '');
		if (subtitleNode)
			subtitleNode.textContent = '长期建议：' + (mediaAi[key + '_long_term_fit'] || '等待进一步检测');
		if (exitNode)
			exitNode.textContent = '建议地区：' + (mediaAi[key + '_recommended_region'] || '稳定国际地区');
		if (latencyNode)
			latencyNode.textContent = mediaAi[key + '_latency_ms'] ? (mediaAi[key + '_latency_ms'] + ' ms') : '-';
		if (httpNode) {
			httpNode.textContent = footer;
			httpNode.style.display = '';
		}
		if (diagnosisNode)
			diagnosisNode.textContent = mediaAi[key + '_diagnosis'] || '等待进一步检测。';
		if (riskNode)
			riskNode.textContent = mediaAi[key + '_native_text'] && mediaAi[key + '_native_text'] !== '不适用'
				? ('解锁判断：' + mediaAi[key + '_native_text'])
				: ('风险判断：' + (mediaAi[key + '_risk_hint'] || '待进一步确认'));
		if (nextNode)
			nextNode.textContent = '下一步：' + (mediaAi[key + '_next_step'] || '建议重跑一次真实检测后再判断。');
	});

	Array.prototype.forEach.call(document.querySelectorAll('[data-media-link-title]'), function(node) {
		var key = node.getAttribute('data-media-link-title');
		node.textContent = isAiMediaTarget(key)
			? (mediaAi[key + '_risk_hint'] || aiServicePurpose(key))
			: (mediaAi[key + '_long_term_fit'] || streamingLongTermLabel(key, mediaAi));
	});

	Array.prototype.forEach.call(document.querySelectorAll('[data-media-link-copy]'), function(node) {
		var key = node.getAttribute('data-media-link-copy');
		node.textContent = isAiMediaTarget(key)
			? ((mediaAi[key + '_diagnosis'] || aiServiceAdvice(key, mediaAi)) + ' 建议地区：' + (mediaAi[key + '_recommended_region'] || aiServiceRegionHint(key)))
			: ((mediaAi[key + '_diagnosis'] || streamingServiceAdvice(key, mediaAi)) + ' ' + (mediaAi[key + '_next_step'] || ''));
	});

	Array.prototype.forEach.call(document.querySelectorAll('[data-media-link-badge]'), function(node) {
		var key = node.getAttribute('data-media-link-badge');
		node.textContent = mediaAi[key + '_status_text'] || '暂无结果';
		node.className = 'oca-badge oca-badge-' + (mediaAi[key + '_tone'] || 'warn');
	});

	Array.prototype.forEach.call(document.querySelectorAll('[data-summary-field]'), function(node) {
		var field = node.getAttribute('data-summary-field');
		if (field === 'progress')
			node.textContent = String(mediaAi.completed_count || 0) + '/' + String(mediaAi.selected_count || 0);
		else if (field === 'success')
			node.textContent = String(mediaAi.success_count || 0);
		else if (field === 'issues')
			node.textContent = String((mediaAi.partial_count || 0) + (mediaAi.issue_count || 0));
		else if (field === 'last_run_at')
			node.textContent = mediaAi.last_run_at || '暂无';
		else if (field === 'summary')
			node.textContent = mediaAi.summary || '-';
		else if (field === 'suggestion')
			node.textContent = mediaAi.suggestion || '-';
	});
}

function startMediaAiPolling(canRun, initialState) {
	if (!canRun || !initialState || !initialState.test_running)
		return;

	var poll = function() {
		fs.exec('/usr/libexec/openclash-assistant/diag.sh', [ 'media-ai-json' ]).then(function(res) {
			var nextMediaAi = safeParse(res.stdout || '{}', {});
			window.__openclashAssistantMediaAiState = nextMediaAi;
			updateAccessCardNodes(nextMediaAi);

			if (nextMediaAi.test_running)
				window.setTimeout(poll, 4000);
		}).catch(function() {});
	};

	window.setTimeout(poll, 4000);
}

function updateSplitTunnelCardNodes(splitTunnel) {
	Array.prototype.forEach.call(document.querySelectorAll('[data-split-card]'), function(card) {
		var key = card.getAttribute('data-split-card');
		var statusNode = card.querySelector('[data-field="status"]');
		var latencyNode = card.querySelector('[data-field="latency"]');
		var exitNode = card.querySelector('[data-field="exit"]');
		var httpNode = card.querySelector('[data-field="http"]');
		var detail = splitTunnel[key + '_detail'] || '';
		var footer = 'HTTP ' + (splitTunnel[key + '_http_code'] || '-');
		var tone = splitTunnel[key + '_tone'] || 'warn';
		var showFooter = tone !== 'good';
		var exitParts = [];
		var flag = countryFlag(splitTunnel[key + '_exit_country']);

		if (splitTunnel[key + '_exit_country'])
			exitParts.push((flag ? flag + ' ' : '') + splitTunnel[key + '_exit_country']);
		if (splitTunnel[key + '_exit_colo'])
			exitParts.push(splitTunnel[key + '_exit_colo']);
		if (splitTunnel[key + '_exit_ip'])
			exitParts.push(splitTunnel[key + '_exit_ip']);

		if (detail && detail !== '-' && detail.indexOf('连接正常') === -1)
			footer += ' · ' + detail;

		if (statusNode) {
			statusNode.textContent = splitTunnel[key + '_status_text'] || '暂无结果';
			statusNode.style.color = toneColor(tone);
		}
		if (latencyNode)
			latencyNode.textContent = splitTunnel[key + '_latency_ms'] ? (splitTunnel[key + '_latency_ms'] + ' ms') : '-';
		if (exitNode) {
			exitNode.textContent = exitParts.length ? exitParts.join(' · ') : '出口信息暂不可用';
			exitNode.style.color = exitParts.length ? '#0f172a' : '#94a3b8';
			exitNode.style.fontWeight = exitParts.length ? '700' : '500';
		}
		if (httpNode) {
			httpNode.textContent = footer;
			httpNode.style.display = showFooter ? '' : 'none';
		}
	});

	Array.prototype.forEach.call(document.querySelectorAll('[data-split-summary]'), function(node) {
		var field = node.getAttribute('data-split-summary');
		if (field === 'summary')
			node.textContent = splitTunnel.summary || '-';
		else if (field === 'last_run_at')
			node.textContent = splitTunnel.last_run_at || '暂无';
	});
}

function startSplitTunnelPolling(initialState) {
	if (!initialState || !initialState.test_running)
		return;
	if (window.__openclashAssistantSplitTunnelPolling)
		return;

	window.__openclashAssistantSplitTunnelPolling = true;

	var poll = function() {
		fs.exec('/usr/libexec/openclash-assistant/diag.sh', [ 'split-tunnel-json' ]).then(function(res) {
			var nextState = safeParse(res.stdout || '{}', {});
			window.__openclashAssistantSplitTunnelState = nextState;
			updateSplitTunnelCardNodes(nextState);

			if (nextState.test_running)
				window.setTimeout(poll, 4000);
			else
				window.__openclashAssistantSplitTunnelPolling = false;
		}).catch(function() {
			window.__openclashAssistantSplitTunnelPolling = false;
		});
	};

	window.setTimeout(poll, 4000);
}

function getSavedTab() {
	try {
		var tab = window.localStorage.getItem('openclash-assistant-tab') || 'subconvert';
		if (tab === 'sub')
			return 'subconvert';
		return tab;
	} catch (error) {
		return 'subconvert';
	}
}

function saveTab(tabKey) {
	try {
		window.localStorage.setItem('openclash-assistant-tab', tabKey);
	} catch (error) {}
}

function getSavedFilter() {
	try {
		return window.localStorage.getItem('openclash-assistant-filter') || 'all';
	} catch (error) {
		return 'all';
	}
}

function saveFilter(filterKey) {
	try {
		window.localStorage.setItem('openclash-assistant-filter', filterKey);
	} catch (error) {}
}

function getSavedDisplayMode() {
	try {
		var mode = window.localStorage.getItem('openclash-assistant-display-mode') || 'simple';
		return mode === 'advanced' ? 'advanced' : 'simple';
	} catch (error) {
		return 'simple';
	}
}

function saveDisplayMode(mode) {
	try {
		window.localStorage.setItem('openclash-assistant-display-mode', mode === 'advanced' ? 'advanced' : 'simple');
	} catch (error) {}
}

function countryFlag(code) {
	if (!code || code.length !== 2)
		return '';

	return code.toUpperCase().replace(/./g, function(char) {
		return String.fromCodePoint(127397 + char.charCodeAt(0));
	});
}

function simpleRoleLabel(role) {
	if (role === 'main_router')
		return '主路由';
	if (role === 'single_arm')
		return '混合模式';
	return '旁路由';
}

function simpleModeLabel(mode) {
	if (mode === 'compatibility')
		return '兼容优先';
	if (mode === 'fake-ip')
		return '性能优先';
	if (mode === 'tun')
		return '全量接管';
	return '自动';
}

function autoGoalLabel(goal) {
	if (goal === 'speed')
		return '速度优先';
	if (goal === 'streaming')
		return '流媒体优先';
	if (goal === 'ai')
		return 'AI 优先';
	if (goal === 'game')
		return '游戏低延迟';
	return '稳定优先';
}

function autoScopeLabel(scope) {
	if (scope === 'same_region')
		return '同地区';
	if (scope === 'global')
		return '全局';
	return '同策略组';
}

function shouldAutoStartChecks(mediaAi, activeTab) {
	if (activeTab !== 'streaming' && activeTab !== 'ai' && activeTab !== 'checkup')
		return false;
	if (mediaAi.test_running)
		return false;
	if (!mediaAi.last_run_at)
		return true;

	var lastRun = new Date(String(mediaAi.last_run_at).replace(' ', 'T'));
	if (isNaN(lastRun.getTime()))
		return true;

	return (Date.now() - lastRun.getTime()) > 60000;
}

var mediaTargets = [
	{ key: 'netflix', label: '奈飞' },
	{ key: 'disney', label: '迪士尼+' },
	{ key: 'youtube', label: '油管会员' },
	{ key: 'prime_video', label: '亚马逊视频' },
	{ key: 'hbo_max', label: 'Max' },
	{ key: 'dazn', label: 'DAZN' },
	{ key: 'paramount_plus', label: '派拉蒙+' },
	{ key: 'discovery_plus', label: '探索+' },
	{ key: 'tvb_anywhere', label: 'TVB Anywhere+' },
	{ key: 'bilibili', label: '哔哩哔哩' },
	{ key: 'openai', label: 'ChatGPT / OpenAI' },
	{ key: 'claude', label: 'Claude' },
	{ key: 'gemini', label: 'Gemini' },
	{ key: 'grok', label: 'Grok' },
	{ key: 'perplexity', label: 'Perplexity' },
	{ key: 'poe', label: 'Poe' },
	{ key: 'cursor', label: 'Cursor' },
	{ key: 'codex', label: 'Codex / API' }
];

var streamingTargets = mediaTargets.filter(function(item) {
	return [ 'openai', 'claude', 'gemini', 'grok', 'perplexity', 'poe', 'cursor', 'codex' ].indexOf(item.key) === -1;
});

var aiTargets = mediaTargets.filter(function(item) {
	return [ 'openai', 'claude', 'gemini', 'grok', 'perplexity', 'poe', 'cursor', 'codex' ].indexOf(item.key) >= 0;
});

var splitTunnelTargets = [
	{ key: 'alibaba', label: '阿里云', group: '国内' },
	{ key: 'netease', label: '网易云音乐', group: '国内' },
	{ key: 'bytedance', label: '字节跳动', group: '国内' },
	{ key: 'tencent', label: '腾讯', group: '国内' },
	{ key: 'qualcomm_cn', label: '高通中国', group: '国内' },
	{ key: 'cloudflare_cn', label: 'Cloudflare 中国网络', group: '国内' },
	{ key: 'cloudflare', label: 'Cloudflare', group: '国际' },
	{ key: 'bytedance_global', label: '字节海外', group: '国际' },
	{ key: 'discord', label: 'Discord', group: '国际' },
	{ key: 'x', label: 'X / Twitter', group: '国际' },
	{ key: 'medium', label: 'Medium', group: '国际' },
	{ key: 'crunchyroll', label: 'Crunchyroll', group: '国际' },
	{ key: 'chatgpt', label: 'ChatGPT', group: 'AI' },
	{ key: 'sora', label: 'Sora', group: 'AI' },
	{ key: 'openai_web', label: 'OpenAI 官网', group: 'AI' },
	{ key: 'claude', label: 'Claude', group: 'AI' },
	{ key: 'grok', label: 'Grok', group: 'AI' },
	{ key: 'anthropic', label: 'Anthropic', group: 'AI' },
	{ key: 'gemini', label: 'Gemini', group: 'AI' },
	{ key: 'perplexity', label: 'Perplexity', group: 'AI' },
	{ key: 'jsdelivr', label: 'jsDelivr', group: '开发 / 静态' },
	{ key: 'cdnjs', label: 'cdnjs', group: '开发 / 静态' },
	{ key: 'cloudflaremirrors', label: 'Cloudflare 镜像', group: '开发 / 静态' },
	{ key: 'npm', label: 'npm Registry', group: '开发 / 静态' },
	{ key: 'kali', label: 'Kali Download', group: '开发 / 静态' },
	{ key: 'unpkg', label: 'unpkg', group: '开发 / 静态' },
	{ key: 'nodejs', label: 'Node.js', group: '开发 / 静态' },
	{ key: 'gitlab', label: 'GitLab', group: '开发 / 静态' },
	{ key: 'coinbase', label: 'Coinbase', group: '加密 / 金融' },
	{ key: 'okx', label: 'OKX', group: '加密 / 金融' }
];

var splitTunnelPrimaryTargets = [
	'cloudflare', 'cloudflare_cn', 'x', 'discord', 'chatgpt', 'claude', 'gemini', 'perplexity', 'gitlab', 'okx'
];

function regionBucket(region) {
	if (!region)
		return '-';

	region = String(region).toUpperCase();
	if (region === 'US')
		return '美区';
	if (region === 'HK')
		return '港区';
	if (region === 'JP')
		return '日区';
	if (region === 'SG')
		return '新加坡';
	if (region === 'TW')
		return '台湾';
	if (region === 'UK' || region === 'GB')
		return '英国';
	return '其他地区';
}

function isIssueStatus(status) {
	return [ 'restricted', 'blocked', 'failed', 'no_unlock', 'other_region', 'homemade_only', 'unknown' ].indexOf(status) >= 0;
}

function countByStatus(items, mediaAi, predicate) {
	return items.filter(function(item) {
		var status = mediaAi[item.key + '_status'] || '';
		return predicate(status);
	}).length;
}

function applyMediaFilter(filterKey) {
	Array.prototype.forEach.call(document.querySelectorAll('[data-media-group]'), function(groupNode) {
		var group = groupNode.getAttribute('data-media-group');
		groupNode.style.display = (filterKey === 'all' || filterKey === group || filterKey === 'issues') ? '' : 'none';
	});

	Array.prototype.forEach.call(document.querySelectorAll('[data-media-card]'), function(card) {
		var status = card.getAttribute('data-media-status') || '';
		if (filterKey === 'issues')
			card.style.display = isIssueStatus(status) ? '' : 'none';
		else
			card.style.display = '';
	});
}

function splitTunnelSortKey(item, splitTunnel) {
	var hasExit = !!(splitTunnel[item.key + '_exit_country'] || splitTunnel[item.key + '_exit_ip'] || splitTunnel[item.key + '_exit_colo']);
	var groupOrder = { '国内': 0, '国际': 1, 'AI': 2, '开发 / 静态': 3, '加密 / 金融': 4, '其他': 5 };
	return [
		hasExit ? 0 : 1,
		groupOrder[item.group] != null ? groupOrder[item.group] : 9,
		item.label
	];
}

function sortSplitTunnelTargets(items, splitTunnel) {
	return items.slice().sort(function(a, b) {
		var ak = splitTunnelSortKey(a, splitTunnel);
		var bk = splitTunnelSortKey(b, splitTunnel);

		for (var i = 0; i < ak.length; i++) {
			if (ak[i] < bk[i]) return -1;
			if (ak[i] > bk[i]) return 1;
		}
		return 0;
	});
}

function checkLevelLabel(level) {
	if (level === 'fix')
		return '需要修复';
	if (level === 'risk')
		return '存在风险';
	if (level === 'optimize')
		return '可优化';
	return '正常';
}

function checkLevelTone(level) {
	if (level === 'fix')
		return 'bad';
	if (level === 'risk')
		return 'warn';
	if (level === 'optimize')
		return 'neutral';
	return 'good';
}

function checkLevelWeight(level) {
	if (level === 'fix')
		return 3;
	if (level === 'risk')
		return 2;
	if (level === 'optimize')
		return 1;
	return 0;
}

function inferCheckup(status, advice, mediaAi, splitTunnel, flushDns, autoSwitch, subconvert) {
	var items = [];
	var overall = 'ok';

	function pushItem(item) {
		items.push(item);
		if (checkLevelWeight(item.level) > checkLevelWeight(overall))
			overall = item.level;
	}

	pushItem({
		key: 'core',
		title: '基础服务',
		level: status.running ? 'ok' : 'fix',
		text: status.running
			? 'OpenClash 当前已经在运行，基础代理服务已经接管。'
			: 'OpenClash 当前没有正常运行，后面的订阅、检测和分流结果都不可靠。',
		next: status.running ? '如果你刚改过配置，建议继续做一次体检确认。' : '先启动 OpenClash，再继续做访问检测。',
		action: status.running ? null : { type: 'tab', tab: 'overview', label: '查看概览' }
	});

	pushItem({
		key: 'subscription',
		title: '订阅导入与转换',
		level: subconvert.source ? (subconvert.enabled ? 'ok' : 'optimize') : 'risk',
		text: subconvert.source
			? (subconvert.enabled ? '已经填写原始订阅地址，并启用了本地转换后端。' : '已经填写订阅，但当前没有启用转换，部分小白模板能力不会生效。')
			: '还没有填写原始订阅地址，首次导入流程还没完成。',
		next: subconvert.source
			? (subconvert.enabled ? '可以继续写入 OpenClash，或者先在内置页面里调整模板。' : '如果你想少折腾，建议打开订阅转换后再导入。')
			: '先到“导入订阅”页填入订阅地址，再生成配置。',
		action: { type: 'tab', tab: 'subconvert', label: subconvert.source ? '去处理订阅' : '去导入订阅' }
	});

	pushItem({
		key: 'dns',
		title: 'DNS 解析状态',
		level: flushDns.dns_diag_level === 'bad' ? 'fix' : (flushDns.dns_diag_level === 'warn' ? 'risk' : 'ok'),
		text: flushDns.dns_diag_level === 'bad'
			? '当前解析链路不完整，容易出现网站打不开、时好时坏的问题。'
			: (flushDns.dns_diag_level === 'warn'
				? '当前解析链路有冲突或存在提示项，可能影响流媒体和 AI 服务。'
				: '当前解析链路基本正常，没有发现明显异常。'),
		next: flushDns.dns_diag_level === 'good'
			? '如果个别网站仍异常，再做一次刷新解析即可。'
			: (flushDns.dns_diag_action || '建议先刷新解析，再重新检测。'),
		action: flushDns.dns_diag_level === 'good'
			? { type: 'tab', tab: 'dns', label: '查看解析页' }
			: { type: 'command', command: 'flush-dns', label: '一键刷新解析' }
	});

	pushItem({
		key: 'streaming',
		title: '流媒体与 AI 连通',
		level: (mediaAi.issue_count || 0) > 0 ? 'risk' : ((mediaAi.success_count || 0) > 0 ? 'ok' : 'optimize'),
		text: (mediaAi.issue_count || 0) > 0
			? '当前至少有一部分流媒体或 AI 服务访问受限，线路不算稳定。'
			: ((mediaAi.success_count || 0) > 0
				? '最近一次检测里，已有服务可以正常访问。'
				: '还没有拿到完整的访问检测结果。'),
		next: (mediaAi.issue_count || 0) > 0
			? '建议先看流媒体页和 AI 页，确认是地区问题还是线路问题。'
			: '如果你准备长期使用，建议主动跑一次专项检测，先把适合的节点挑出来。',
		action: { type: 'tab', tab: (mediaAi.issue_count || 0) > 0 ? 'streaming' : 'checkup', label: (mediaAi.issue_count || 0) > 0 ? '查看专项检测' : '去做体检' }
	});

	pushItem({
		key: 'split',
		title: '网站走向检测',
		level: (splitTunnel.success_count || 0) > 0 ? ((splitTunnel.issue_count || 0) > 0 ? 'optimize' : 'ok') : 'optimize',
		text: (splitTunnel.success_count || 0) > 0
			? '已经拿到一批网站走向结果，可以用来确认国内、国外和 AI 站点是否按预期出站。'
			: '还没有运行网站走向检测，暂时无法判断某些网站为什么打不开。',
		next: (splitTunnel.success_count || 0) > 0
			? '如果发现走向不合理，再去调整配置或切换模板。'
			: '建议至少跑一次网站走向检测，确认网站到底走了哪条路。',
		action: { type: 'tab', tab: 'split', label: '去看网站走向' }
	});

	pushItem({
		key: 'switch',
		title: '自动切换建议',
		level: autoSwitch.enabled && status.stream_auto_select !== '1' ? 'optimize' : 'ok',
		text: autoSwitch.enabled
			? '系统已经给出自动切换建议，可以减少节点忽好忽坏时的手动操作。'
			: '当前没有强制建议开启自动切换，适合更保守的使用方式。',
		next: autoSwitch.enabled && status.stream_auto_select !== '1'
			? '如果你节点多、线路波动大，建议应用自动切换。'
			: '如果你更在意稳定，保持当前设置也可以。',
		action: autoSwitch.enabled && status.stream_auto_select !== '1'
			? { type: 'command', command: 'apply-auto-switch', label: '应用自动切换' }
			: { type: 'tab', tab: 'auto', label: '查看自动切换' }
	});

	var summary = '当前整体状态正常，可以继续使用。';
	if (overall === 'fix')
		summary = '当前有需要优先修复的问题，建议先处理基础服务或 DNS。';
	else if (overall === 'risk')
		summary = '当前能用，但存在影响体验的风险项，建议继续做专项检测。';
	else if (overall === 'optimize')
		summary = '当前基本可用，适合继续按用途优化线路和配置。';

	return {
		overall: overall,
		summary: summary,
		items: items
	};
}

return view.extend({
	load: function() {
		var cachedStatus = readCachedJson('openclash-assistant-cache-status', {});
		var cachedMediaAi = readCachedJson('openclash-assistant-cache-media-ai', {});
		var cachedSplitTunnel = readCachedJson('openclash-assistant-cache-split-tunnel', {});
		var cachedFlushDns = readCachedJson('openclash-assistant-cache-flush-dns', {});
		var cachedTemplates = readCachedJson('openclash-assistant-cache-templates', { templates: [] });
		var cachedAutoSwitch = readCachedJson('openclash-assistant-cache-auto-switch-lite', {});
		var cachedSubconvert = readCachedJson('openclash-assistant-cache-subconvert-lite', {});

		return Promise.all([
			withTimeout(
				fs.exec('/usr/libexec/openclash-assistant/diag.sh', [ 'status-json' ]),
				1500,
				{ stdout: JSON.stringify(cachedStatus || {}) }
			),
			Promise.resolve({ stdout: '{}' }),
			Promise.resolve({ stdout: '{}' }),
			withTimeout(
				fs.exec('/usr/libexec/openclash-assistant/diag.sh', [ 'media-ai-json' ]),
				1500,
				{ stdout: JSON.stringify(cachedMediaAi || {}) }
			),
			withTimeout(
				fs.exec('/usr/libexec/openclash-assistant/diag.sh', [ 'split-tunnel-json' ]),
				1500,
				{ stdout: JSON.stringify(cachedSplitTunnel || {}) }
			),
			withTimeout(
				fs.exec('/usr/libexec/openclash-assistant/diag.sh', [ 'flush-dns-json' ]),
				1500,
				{ stdout: JSON.stringify(cachedFlushDns || {}) }
			),
			withTimeout(
				fs.exec('/usr/libexec/openclash-assistant/diag.sh', [ 'templates-json' ]),
				1500,
				{ stdout: JSON.stringify(cachedTemplates || { templates: [] }) }
			),
			withTimeout(
				fs.exec('/usr/libexec/openclash-assistant/diag.sh', [ 'auto-switch-lite-json' ]),
				1500,
				{ stdout: JSON.stringify(cachedAutoSwitch || {}) }
			),
			withTimeout(
				fs.exec('/usr/libexec/openclash-assistant/diag.sh', [ 'subconvert-lite-json' ]),
				1500,
				{ stdout: JSON.stringify(cachedSubconvert || {}) }
			)
		]);
	},

	render: function(data) {
		var status = safeParse(data[0].stdout || '{}', {});
		var checkupData = safeParse(data[1].stdout || '{}', {});
		var advice = safeParse(data[2].stdout || '{}', {});
		var mediaAi = safeParse(data[3].stdout || '{}', {});
		var currentMediaAi = mediaAi;
		window.__openclashAssistantMediaAiState = mediaAi;
		var splitTunnel = safeParse(data[4].stdout || '{}', {});
		window.__openclashAssistantSplitTunnelState = splitTunnel;
		var flushDns = safeParse(data[5].stdout || '{}', {});
		var templatesData = safeParse(data[6].stdout || '{"templates":[]}', { templates: [] });
		var autoSwitch = safeParse(data[7].stdout || '{}', {});
		var subconvert = safeParse(data[8].stdout || '{}', {});
		var templates = templatesData.templates || [];

		if (Object.keys(status).length)
			writeCachedJson('openclash-assistant-cache-status', status);
		if (Object.keys(mediaAi).length)
			writeCachedJson('openclash-assistant-cache-media-ai', mediaAi);
		if (Object.keys(splitTunnel).length)
			writeCachedJson('openclash-assistant-cache-split-tunnel', splitTunnel);
		if (Object.keys(flushDns).length)
			writeCachedJson('openclash-assistant-cache-flush-dns', flushDns);
		if (Object.keys(templatesData).length)
			writeCachedJson('openclash-assistant-cache-templates', templatesData);
		if (Object.keys(autoSwitch).length)
			writeCachedJson('openclash-assistant-cache-auto-switch-lite', autoSwitch);
		if (Object.keys(subconvert).length)
			writeCachedJson('openclash-assistant-cache-subconvert-lite', subconvert);

		var map = new form.Map('openclash-assistant', 'OpenClash 助手',
			'给不会折腾配置的人用的上网助手。先导入订阅，再按用途生成配置，最后做检测和修复。');

		var option;
		var topologySection = map.section(form.TypedSection, 'assistant', '一、你的网络怎么接', '先告诉助手 OpenClash 在你的网络里扮演什么角色，后面的建议会更贴近实际情况。');
		topologySection.anonymous = true;
		topologySection.addremove = false;

		option = describeOption(topologySection.option(form.ListValue, 'routing_role', '当前接入方式'),
			'如果你不确定，家用软路由大多是旁路由。');
		option.value('bypass_router', '旁路由');
		option.value('main_router', '主路由');
		option.value('single_arm', '单臂 / 混合模式');
		option.default = 'bypass_router';

		option = describeOption(topologySection.option(form.ListValue, 'preferred_mode', '更看重什么'),
			'小白建议先选自动；如果你更怕兼容问题，就选兼容优先。');
		option.value('auto', '自动');
		option.value('fake-ip', '性能优先');
		option.value('tun', '全量接管');
		option.value('compatibility', '兼容优先');
		option.default = 'auto';

		var compatibilitySection = map.section(form.TypedSection, 'assistant', '二、你的使用场景', '这些选项用来告诉助手你家里还有哪些特殊设备或需求。');
		compatibilitySection.anonymous = true;
		compatibilitySection.addremove = false;

		option = describeOption(compatibilitySection.option(form.Flag, 'needs_ipv6', '家里或公司需要 IPv6'),
			'如果你明确知道自己的宽带和目标服务需要 IPv6，就打开。');
		option.default = '0';
		option = describeOption(compatibilitySection.option(form.Flag, 'has_public_services', '需要从外网访问家里的设备'),
			'例如 NAS、监控、远程桌面，需要从公司或手机流量访问家里。');
		option.default = '0';
		option = describeOption(compatibilitySection.option(form.Flag, 'uses_tailscale', '在用异地组网或远程组网'),
			'如果你在用 Tailscale、ZeroTier 之类的工具，建议打开。');
		option.default = '0';
		option = describeOption(compatibilitySection.option(form.Flag, 'gaming_devices', '家里有游戏机或掌机'),
			'游戏设备通常更怕网络波动，打开后建议会更保守。');
		option.default = '0';

		var preferenceSection = map.section(form.TypedSection, 'assistant', '三、你更想省心还是折腾', '这一组决定助手是更偏稳定，还是给你更多可调空间。');
		preferenceSection.anonymous = true;
		preferenceSection.addremove = false;

		option = describeOption(preferenceSection.option(form.Flag, 'low_maintenance', '希望少折腾、长期稳定'),
			'开启后优先给出更稳妥、更不容易出问题的方案。');
		option.default = '1';

		var streamingSection = map.section(form.TypedSection, 'assistant', '四、流媒体检测');
		streamingSection.anonymous = true;
		streamingSection.addremove = false;

		option = describeOption(streamingSection.option(form.Flag, 'media_ai_enabled', '启用流媒体 / AI 检测建议'),
			'如果你想看视频和 AI 服务是否适合当前线路，就保持开启。');
		option.default = '1';

		option = streamingSection.option(form.DummyValue, '_streaming_auto_note', '检测方式');
		option.rawhtml = true;
		option.cfgvalue = function() {
			return '这里只决定检测哪些服务。小白模式下默认不用改。';
		};

		[
			[ 'media_detect_netflix', '检测 Netflix' ],
			[ 'media_detect_disney', '检测 Disney+' ],
			[ 'media_detect_youtube', '检测 YouTube Premium' ],
			[ 'media_detect_prime_video', '检测 Prime Video' ],
			[ 'media_detect_hbo_max', '检测 HBO Max' ],
			[ 'media_detect_dazn', '检测 DAZN' ],
			[ 'media_detect_paramount_plus', '检测 Paramount+' ],
			[ 'media_detect_discovery_plus', '检测 Discovery+' ],
			[ 'media_detect_tvb_anywhere', '检测 TVB Anywhere+' ],
			[ 'media_detect_bilibili', '检测 Bilibili' ]
		].forEach(function(item) {
			option = describeOption(streamingSection.option(form.Flag, item[0], item[1]),
				'关闭后就不会再检测这一项服务。');
			option.default = '1';
		});

		var aiSection = map.section(form.TypedSection, 'assistant', '五、AI 检测');
		aiSection.anonymous = true;
		aiSection.addremove = false;

		option = aiSection.option(form.DummyValue, '_ai_hint', '检测方式');
		option.rawhtml = true;
		option.cfgvalue = function() {
			return '这里只决定检测哪些 AI 服务。小白模式下默认不用改。';
		};

		[
			[ 'ai_detect_openai', '检测 OpenAI' ],
			[ 'ai_detect_claude', '检测 Claude' ],
			[ 'ai_detect_gemini', '检测 Gemini' ],
			[ 'ai_detect_grok', '检测 Grok' ],
			[ 'ai_detect_perplexity', '检测 Perplexity' ],
			[ 'ai_detect_poe', '检测 Poe' ],
			[ 'ai_detect_cursor', '检测 Cursor' ],
			[ 'ai_detect_codex', '检测 Codex / API' ]
		].forEach(function(item) {
			option = describeOption(aiSection.option(form.Flag, item[0], item[1]),
				'关闭后就不会再检测这一项服务。');
			option.default = '1';
		});

		option = describeOption(aiSection.option(form.Value, 'media_ai_group_filter', '只检查指定分组'),
			'高级用法。只在你明确知道自己想检查哪些分组时再填。');
		option.placeholder = '例如：Auto, HK, US';
		option = describeOption(aiSection.option(form.Value, 'media_ai_region_filter', '只检查指定地区'),
			'高级用法。比如只看日本或美国节点。');
		option.placeholder = '例如：HK, SG, JP';
		option = describeOption(aiSection.option(form.Value, 'media_ai_node_filter', '只检查指定线路'),
			'高级用法。比如只看 BGP、IEPL 之类的线路。');
		option.placeholder = '例如：BGP, IEPL';

		var autoSection = map.section(form.TypedSection, 'assistant', '六、自动切换建议');
		autoSection.anonymous = true;
		autoSection.addremove = false;
		option = describeOption(autoSection.option(form.Flag, 'auto_switch_enabled', '允许助手推荐自动切换'),
			'如果你节点很多，打开后会更省心。');
		option.default = '1';
		option = describeOption(autoSection.option(form.ListValue, 'auto_switch_goal', '你更想优先保障什么'),
			'这是自动切换向导的核心目标。小白默认建议选“稳定优先”。');
		option.value('stability', '稳定优先');
		option.value('speed', '速度优先');
		option.value('streaming', '流媒体优先');
		option.value('ai', 'AI 优先');
		option.value('game', '游戏低延迟');
		option.default = 'stability';
		option = describeOption(autoSection.option(form.ListValue, 'auto_switch_logic', '底层切换方式'),
			'默认建议选延迟优先，更适合大多数人。随机轮换更像实验模式。');
		option.value('urltest', '速度优先');
		option.value('random', '随机轮换');
		option.default = 'urltest';
		option = describeOption(autoSection.option(form.ListValue, 'auto_switch_scope', '允许在哪些节点里切换'),
			'范围越大，越容易找到可用节点，但也越容易切到不符合你用途的线路。');
		option.value('same_group', '同策略组');
		option.value('same_region', '同地区');
		option.value('global', '全局');
		option.default = 'same_group';
		option = describeOption(autoSection.option(form.Value, 'auto_switch_interval', '多久检查一次（分钟）'),
			'检查太频繁会更折腾，默认 30 分钟更稳妥。');
		option.datatype = 'uinteger';
		option.default = '30';
		option = describeOption(autoSection.option(form.Value, 'auto_switch_latency_threshold', '延迟超过多少就考虑切换（毫秒）'),
			'如果你更在意稳定，可适当放宽；如果你更在意游戏或实时体验，可适当收紧。');
		option.datatype = 'uinteger';
		option.default = '180';
		option = describeOption(autoSection.option(form.Value, 'auto_switch_packet_loss_threshold', '丢包率超过多少就考虑切换（%）'),
			'这个值越低，越容易触发切换。普通家用默认 20% 已经足够。');
		option.datatype = 'uinteger';
		option.default = '20';
		option = describeOption(autoSection.option(form.ListValue, 'auto_switch_fail_threshold', '连续失败几次后切换'),
			'如果你更怕误切，可以把失败次数设高一点。');
		option.value('1', '1 次');
		option.value('2', '2 次');
		option.value('3', '3 次');
		option.value('5', '5 次');
		option.default = '2';
		option = describeOption(autoSection.option(form.Flag, 'auto_switch_revert_preferred', '恢复后允许回切首选节点'),
			'打开后，线路恢复时会尽量回到更符合你偏好的节点。');
		option.default = '1';
		option = describeOption(autoSection.option(form.Flag, 'auto_switch_expand_group', '允许扩大候选范围'),
			'打开后，自动切换可用的候选节点会更多。');
		option.default = '1';
		option = describeOption(autoSection.option(form.Flag, 'auto_switch_close_con', '切换后清理旧连接'),
			'打开后切换更干净，但个别网页或下载可能需要重新连。');
		option.default = '1';

		var subSection = map.section(form.TypedSection, 'assistant', '七、订阅导入与转换');
		subSection.anonymous = true;
		subSection.addremove = false;
		option = describeOption(subSection.option(form.Flag, 'sub_convert_enabled', '导入前先整理订阅'),
			'建议保持开启，这样更适合小白使用。');
		option.default = '1';
		option = describeOption(subSection.option(form.Value, 'sub_convert_source', '原始订阅地址'),
			'把机场给你的原始订阅链接粘贴到这里。');
		option.placeholder = 'https://example.com/sub?...';
		option = describeOption(subSection.option(form.Value, 'sub_convert_backend', '本地转换服务地址'),
			'默认不用改，保持本机转换即可。');
		option.placeholder = 'http://127.0.0.1:25500';
		option.default = 'http://127.0.0.1:25500';
		option = describeOption(subSection.option(form.ListValue, 'sub_convert_template', '转换模板'),
			'模板决定生成出来的配置更偏日常、流媒体、AI 还是稳定。');
		templates.forEach(function(item) {
			option.value(item.id, item.name);
		});
		option.value('custom', '自定义模板');
		option.default = 'ACL4SSR_Online_Mini_MultiMode.ini';
		option = describeOption(subSection.option(form.Value, 'sub_convert_custom_template_url', '自定义模板地址'),
			'当上面选择“自定义模板”时，在这里填完整 ini 地址。');
		option.placeholder = 'https://raw.githubusercontent.com/...';
		option.depends('sub_convert_template', 'custom');
		option = describeOption(subSection.option(form.ListValue, 'sub_convert_emoji', '节点名加地区图标'),
			'打开后更容易看出节点是哪个地区。');
		option.value('false', '关闭');
		option.value('true', '开启');
		option.default = 'true';
		option = describeOption(subSection.option(form.ListValue, 'sub_convert_udp', '保留游戏和视频需要的连接能力'),
			'大多数场景建议开启。');
		option.value('false', '关闭');
		option.value('true', '开启');
		option.default = 'true';
		option = describeOption(subSection.option(form.ListValue, 'sub_convert_sort', '让转换结果更规整'),
			'打开后更整齐，但可能改变原始节点顺序。');
		option.value('false', '关闭');
		option.value('true', '开启');
		option.default = 'false';
		option = describeOption(subSection.option(form.ListValue, 'sub_convert_skip_cert_verify', '兼容异常证书'),
			'只有在订阅源证书有问题时才建议打开。');
		option.value('false', '关闭');
		option.value('true', '开启');
		option.default = 'false';
		option = describeOption(subSection.option(form.ListValue, 'sub_convert_append_node_type', '节点名显示线路类型'),
			'打开后更方便人工区分不同类型线路。');
		option.value('false', '关闭');
		option.value('true', '开启');
		option.default = 'true';

		var actionOpenTab = function() {};
		var runAction = function(action) {
			return fs.exec('/usr/libexec/openclash-assistant/diag.sh', [ action ]).then(function(res) {
				var result = safeParse(res.stdout || '{}', {});
				window.alert(result.message || '执行完成');
				if (action === 'run-media-ai-live-test') {
					window.__openclashAssistantMediaAiState = { test_running: true };
					actionOpenTab('streaming');
					startMediaAiPolling(true, { test_running: true });
					return result;
				}
				if (action === 'run-split-tunnel-test') {
					window.__openclashAssistantSplitTunnelState = { test_running: true };
					actionOpenTab('split');
					startSplitTunnelPolling({ test_running: true });
					return result;
				}
				if ([ 'restart-openclash', 'auto-fix-basic', 'apply-auto-switch', 'apply-recommended-profile', 'apply-subconvert', 'sync-subconvert-from-openclash' ].indexOf(action) >= 0) {
					window.setTimeout(function() { window.location.reload(); }, 800);
				}
				return result;
			}).catch(function(err) {
				window.alert('执行失败：' + err);
				throw err;
			});
		};

		return map.render().then(function(node) {
			ensureOverviewTheme();
			node.classList.add('oca-shell');
			var displayMode = getSavedDisplayMode();
			node.setAttribute('data-display-mode', displayMode);

			var streamingSuccessCount = countByStatus(streamingTargets, mediaAi, function(itemStatus) {
				return itemStatus === 'reachable' || itemStatus === 'available' || itemStatus === 'full_support';
			});
			var streamingIssueCount = countByStatus(streamingTargets, mediaAi, isIssueStatus);
			var aiSuccessCount = countByStatus(aiTargets, mediaAi, function(itemStatus) {
				return itemStatus === 'reachable' || itemStatus === 'available' || itemStatus === 'full_support';
			});
			var aiIssueCount = countByStatus(aiTargets, mediaAi, isIssueStatus);
			var embeddedFrontendUrl = buildEmbeddedFrontendUrl(subconvert);
			var subHistory = Array.isArray(subconvert.history) ? subconvert.history : [];
			var checkupModel = (checkupData && checkupData.items && checkupData.items.length)
				? checkupData
				: inferCheckup(status, advice, mediaAi, splitTunnel, flushDns, autoSwitch, subconvert);
			var adviceItems = Array.isArray(advice.items) ? advice.items : [];
			var adviceOverallLevel = advice.overall_level || 'ok';
			var adviceActionableCount = adviceItems.filter(function(item) {
				return item.level && item.level !== 'ok';
			}).length;
			var checkupPrimaryItem = (checkupModel.items || []).reduce(function(best, item) {
				if (!item || item.level === 'ok')
					return best;
				if (!best || checkLevelWeight(item.level) > checkLevelWeight(best.level))
					return item;
				return best;
			}, null);

			var openTab = function() {};
			var triggerMediaChecks = function() {};
			var triggerSplitChecks = function() {};
			var runAssistantCheckup = function() {};
			var updateLiveSummaryCards = function(nextStatus, nextSubconvert) {
				updateStatusCardNodes(nextStatus || {});
				updateSubconvertCardNodes(nextSubconvert || {});
			};

			var setDisplayMode = function(mode) {
				displayMode = mode === 'advanced' ? 'advanced' : 'simple';
				node.setAttribute('data-display-mode', displayMode);
				saveDisplayMode(displayMode);
				Array.prototype.forEach.call(node.querySelectorAll('[data-mode-chip]'), function(chip) {
					if (chip.getAttribute('data-mode-chip') === displayMode)
						chip.classList.add('active');
					else
						chip.classList.remove('active');
				});
			};

			var makeActionForItem = function(item) {
				if (!item || !item.action)
					return null;

				if (item.action.type === 'command') {
					return actionButton(item.action.label, function() {
						runAction(item.action.command);
					}, 'secondary');
				}

				return actionButton(item.action.label, function() {
					openTab(item.action.tab);
				}, 'ghost');
			};

			var makeMediaResultCards = function(items) {
				return E('div', { 'class': 'oca-grid' }, items.map(function(item) {
					var tone = mediaAi[item.key + '_tone'] || 'warn';
					var longTermFit = mediaAi[item.key + '_long_term_fit']
						|| (isAiMediaTarget(item.key) ? '等待进一步检测' : streamingLongTermLabel(item.key, mediaAi));
					var diagnosis = mediaAi[item.key + '_diagnosis']
						|| (isAiMediaTarget(item.key) ? aiServiceAdvice(item.key, mediaAi) : streamingServiceAdvice(item.key, mediaAi));
					var transportText = 'DNS ' + (mediaAi[item.key + '_dns_state'] || '未检测')
						+ ' · TLS ' + (mediaAi[item.key + '_tls_state'] || '未检测')
						+ ' · ' + (mediaAi[item.key + '_http_state'] || ('HTTP ' + (mediaAi[item.key + '_http_code'] || '-')));
					var riskOrNative = mediaAi[item.key + '_native_text'] && mediaAi[item.key + '_native_text'] !== '不适用'
						? ('解锁判断：' + mediaAi[item.key + '_native_text'])
						: ('风险判断：' + (mediaAi[item.key + '_risk_hint'] || '待进一步确认'));

					return infoCard({
						title: item.label,
						subtitle: '长期建议：' + longTermFit,
						status: mediaAi[item.key + '_status_text'] || '暂无结果',
						statusColor: toneColor(tone),
						exit: '建议地区：' + (mediaAi[item.key + '_recommended_region'] || aiServiceRegionHint(item.key)),
						value: mediaAi[item.key + '_latency_ms'] ? (mediaAi[item.key + '_latency_ms'] + ' ms') : '-',
						footer: transportText,
						extraNode: E('div', { 'class': 'oca-card-meta' }, [
							E('div', { 'class': 'oca-link-copy', 'data-field': 'diagnosis' }, diagnosis),
							E('div', { 'class': 'oca-link-copy', 'data-field': 'risk' }, riskOrNative),
							E('div', { 'class': 'oca-link-copy', 'data-field': 'next' }, '下一步：' + (mediaAi[item.key + '_next_step'] || '建议重跑一次真实检测后再判断。'))
						]),
						attrs: {
							'data-media-card': item.key,
							'data-media-status': mediaAi[item.key + '_status'] || ''
						}
					});
				}));
			};

			var makeSplitTunnelCards = function(items) {
				return E('div', { 'class': 'oca-grid' }, items.map(function(item) {
					var tone = splitTunnel[item.key + '_tone'] || 'warn';
					var detail = splitTunnel[item.key + '_detail'] || '';
					var footer = 'HTTP ' + (splitTunnel[item.key + '_http_code'] || '-');
					var showFooter = tone !== 'good';
					var exitParts = [];
					var flag = countryFlag(splitTunnel[item.key + '_exit_country']);

					if (splitTunnel[item.key + '_exit_country'])
						exitParts.push((flag ? flag + ' ' : '') + splitTunnel[item.key + '_exit_country']);
					if (splitTunnel[item.key + '_exit_colo'])
						exitParts.push(splitTunnel[item.key + '_exit_colo']);
					if (splitTunnel[item.key + '_exit_ip'])
						exitParts.push(splitTunnel[item.key + '_exit_ip']);

					if (detail && detail !== '-' && detail.indexOf('连接正常') === -1)
						footer += ' · ' + detail;

					var isPrimary = splitTunnelPrimaryTargets.indexOf(item.key) >= 0;

					return infoCard({
						title: item.label,
						subtitle: item.group,
						status: splitTunnel[item.key + '_status_text'] || '暂无结果',
						statusColor: toneColor(tone),
						exit: exitParts.length ? exitParts.join(' / ') : '出口信息暂不可用',
						exitStyle: 'font-size:' + (isPrimary ? '13px' : '11px') + ';color:' + (exitParts.length ? '#0f172a' : '#94a3b8') + ';font-weight:' + (exitParts.length ? '700' : '500') + ';',
						value: splitTunnel[item.key + '_latency_ms'] ? (splitTunnel[item.key + '_latency_ms'] + ' ms') : '-',
						footer: footer,
						footerHidden: !showFooter,
						attrs: { 'data-split-card': item.key }
					});
				}));
			};

			var makeRecommendationItem = function(title, value, note) {
				return E('div', { 'class': 'oca-recommend-item' }, [
					E('div', { 'class': 'oca-recommend-title' }, title),
					E('div', { 'class': 'oca-recommend-value' }, value || '-'),
					E('div', { 'class': 'oca-recommend-note' }, note || '保持默认即可。')
				]);
			};

			var subconvertPreviewWrap = null;
			var ensureSubconvertPreviewLoaded = function() {
				if (!subconvertPreviewWrap)
					return;
				if (subconvertPreviewWrap.getAttribute('data-preview-loaded') === '1')
					return;

				while (subconvertPreviewWrap.firstChild)
					subconvertPreviewWrap.removeChild(subconvertPreviewWrap.firstChild);

				subconvertPreviewWrap.appendChild(E('iframe', { 'src': embeddedFrontendUrl }));
				subconvertPreviewWrap.setAttribute('data-preview-loaded', '1');
			};

			var renderRouteTestResult = function(result) {
				if (!result || !result.ok)
					return callout((result && result.message) || '请输入你想检测的网站或服务。', 'warn');

				var exitValue = '暂未识别';
				var exitFooter = result.actual_route === 'direct'
					? '当前更像本地直连出口'
					: '这次没有拿到稳定出口信息';
				var exitParts = [];

				if (result.exit_country)
					exitParts.push((countryFlag(result.exit_country) ? (countryFlag(result.exit_country) + ' ') : '') + result.exit_country);
				if (result.exit_colo)
					exitParts.push(result.exit_colo);
				if (result.exit_ip)
					exitParts.push(result.exit_ip);
				if (exitParts.length) {
					exitValue = exitParts.join(' / ');
					exitFooter = result.chain_summary || '已经抓到这次的走向链路';
				}

				return E('div', { 'class': 'oca-route-result' }, [
					E('div', { 'class': 'oca-summary-card', 'style': 'margin-bottom:14px;' }, [
						E('div', { 'class': 'oca-summary-eyebrow' }, '单站点检测结果'),
						E('div', { 'class': 'oca-summary-title' }, result.label || result.host || '网站走向检测'),
						E('p', { 'class': 'oca-summary-copy' }, result.route_summary || result.fit_text || '已经完成这次检测。'),
						E('p', [
							badge(result.status_text || '暂无结果', result.tone || 'warn'),
							badge(routeFitLabel(result.fit), routeFitTone(result.fit)),
							badge(result.matched_group ? ('命中分组：' + result.matched_group) : '暂未抓到分组', result.matched_group ? 'good' : 'warn')
						])
					]),
					E('div', { 'class': 'oca-grid' }, [
						infoCard({
							title: '连通结果',
							value: result.status_text || '暂无结果',
							footer: result.http_code ? ('HTTP ' + result.http_code + (result.latency_ms ? (' / ' + result.latency_ms + ' ms') : '')) : (result.detail || '-'),
							hero: true
						}),
						infoCard({
							title: '建议走向',
							value: routeKindLabel(result.expected_route),
							footer: result.expected_copy || '-',
							hero: true
						}),
						infoCard({
							title: '实际走向',
							value: routeKindLabel(result.actual_route),
							footer: result.fit_text || '-',
							hero: true
						}),
						infoCard({
							title: '最终出口',
							value: exitValue,
							valueClass: 'is-compact',
							footer: exitFooter,
							hero: true
						})
					]),
					E('div', { 'class': 'oca-link-list' }, [
						E('div', { 'class': 'oca-link-item' }, [
							E('div', null, [
								E('div', { 'class': 'oca-link-title' }, '命中了什么'),
								E('div', { 'class': 'oca-link-copy' }, result.matched_rule_text || '这次没抓到明确的规则命中。')
							])
						]),
						E('div', { 'class': 'oca-link-item' }, [
							E('div', null, [
								E('div', { 'class': 'oca-link-title' }, '最终从哪里走'),
								E('div', { 'class': 'oca-link-copy' }, result.chain_summary || result.actual_route_text || '暂未抓到完整链路。')
							])
						]),
						E('div', { 'class': 'oca-link-item' }, [
							E('div', null, [
								E('div', { 'class': 'oca-link-title' }, '助手建议'),
								E('div', { 'class': 'oca-link-copy' }, result.recommendation || '-')
							])
						]),
						E('div', { 'class': 'oca-link-item' }, [
							E('div', null, [
								E('div', { 'class': 'oca-link-title' }, '下一步怎么做'),
								E('div', { 'class': 'oca-link-copy' }, result.next_step || '-')
							])
						])
					]),
					E('div', { 'class': 'oca-advanced-only' }, [
						dataTable([
							E('tr', [ E('td', '输入内容'), E('td', result.input || '-') ]),
							E('tr', [ E('td', '检测地址'), E('td', result.url || '-') ]),
							E('tr', [ E('td', '域名'), E('td', result.host || '-') ]),
							E('tr', [ E('td', '命中规则'), E('td', result.matched_rule_text || '-') ]),
							E('tr', [ E('td', '命中分组'), E('td', result.matched_group || '-') ]),
							E('tr', [ E('td', '最终节点'), E('td', result.matched_node || '-') ]),
							E('tr', [ E('td', 'DNS 模式'), E('td', result.dns_mode || '-') ]),
							E('tr', [ E('td', '目标 IP'), E('td', result.destination_ip || '-') ]),
							E('tr', [ E('td', '远端地址'), E('td', result.remote_destination || '-') ]),
							E('tr', [ E('td', '连接时间'), E('td', result.started_at || '-') ])
						])
					])
				]);
			};

			var checkupCards = E('div', { 'class': 'cbi-section oca-panel' }, [
				E('h3', '一键体检'),
				E('p', [
					badge(checkLevelLabel(checkupModel.overall), checkLevelTone(checkupModel.overall)),
					badge('可自动处理 ' + String(checkupModel.repairable_count || 0), (checkupModel.repairable_count || 0) > 0 ? 'warn' : 'good'),
					badge('流媒体可用 ' + String(streamingSuccessCount), streamingSuccessCount > 0 ? 'good' : 'warn'),
					badge('AI 可用 ' + String(aiSuccessCount), aiSuccessCount > 0 ? 'good' : 'warn')
				]),
				subtleText(checkupModel.summary),
				checkupPrimaryItem ? E('div', { 'class': 'oca-summary-card', 'style': 'margin-top:12px;' }, [
					E('div', { 'class': 'oca-summary-eyebrow' }, '当前优先处理'),
					E('div', { 'class': 'oca-summary-title' }, checkupPrimaryItem.title),
					E('p', { 'class': 'oca-summary-copy' }, checkupPrimaryItem.text),
					E('p', { 'class': 'oca-summary-copy', 'style': 'margin-top:8px;' }, '下一步：' + checkupPrimaryItem.next),
					makeActionForItem(checkupPrimaryItem) || E('div')
				]) : E('div'),
				actionButton('重新跑一键体检', function() {
					runAssistantCheckup();
				}, 'secondary'),
				actionButton('一键修复可自动处理项', function() {
					runAction('auto-fix-basic');
				}, (checkupModel.repairable_count || 0) > 0 ? 'primary' : 'ghost'),
				E('div', { 'class': 'oca-checkup-list' }, checkupModel.items.map(function(item) {
					var actionNode = makeActionForItem(item);
					return E('div', { 'class': 'oca-checkup-item' }, [
						E('div', { 'class': 'oca-checkup-head' }, [
							E('div', { 'class': 'oca-checkup-title' }, item.title),
							badge(checkLevelLabel(item.level), checkLevelTone(item.level))
						]),
						E('div', { 'class': 'oca-checkup-text' }, item.text),
						E('div', { 'class': 'oca-checkup-next' }, '下一步：' + item.next),
						actionNode ? E('div', null, [ actionNode ]) : E('div')
					]);
				}))
			]);

			var statusCards = E('div', { 'class': 'cbi-section oca-panel' }, [
				E('h3', '运行状态概览'),
				E('p', [
					(function() {
						var node = badge(status.running ? 'OpenClash 正在运行' : 'OpenClash 未运行', status.running ? 'good' : 'bad');
						node.setAttribute('data-status-badge', 'running');
						return node;
					})(),
					(function() {
						var node = badge(status.dns_diag_level === 'good' ? '解析基本正常' : '解析需要关注', status.dns_diag_level === 'good' ? 'good' : 'warn');
						node.setAttribute('data-status-badge', 'dns');
						return node;
					})(),
					(function() {
						var node = badge(status.stream_auto_select === '1' ? '已开启自动切换' : '未开启自动切换', status.stream_auto_select === '1' ? 'good' : 'warn');
						node.setAttribute('data-status-badge', 'auto');
						return node;
					})()
				]),
				subtleText(status.running
					? '基础服务已经启动，可以继续看当前配置、检测结果和建议。'
					: '基础服务还没准备好，建议先修复运行状态，再做更深的检测。'),
				E('div', { 'class': 'oca-grid' }, [
					infoCard({ title: '当前运行状态', value: status.running ? '正常' : '未启动', footer: status.dns_diag_summary || '-', hero: true, attrs: { 'data-status-card': 'running' } }),
					infoCard({ title: '部署角色', value: simpleRoleLabel(status.routing_role), footer: '来自当前基础场景配置', hero: true, attrs: { 'data-status-card': 'role' } }),
					infoCard({ title: '当前风格', value: simpleModeLabel(status.preferred_mode), footer: '当前建议会参考这个偏好', hero: true, attrs: { 'data-status-card': 'mode' } }),
					infoCard({ title: '当前默认节点', value: status.current_node || '暂未识别', valueClass: 'is-compact', footer: status.current_node_delay ? ('最近延迟 ' + status.current_node_delay + ' ms') : '还没有拿到节点延迟', hero: true, attrs: { 'data-status-card': 'node' } }),
					infoCard({ title: '出口地区 / IP', value: (status.exit_country || '-') + (status.exit_colo ? (' / ' + status.exit_colo) : ''), footer: status.exit_ip || '暂未识别出口 IP', hero: true, attrs: { 'data-status-card': 'exit' } }),
					infoCard({ title: '资源占用', value: (status.cpu_pct || '-') + '% / ' + (status.mem_pct || '-') + '%', footer: (status.clash_mem_mb ? ('Clash 内存 ' + status.clash_mem_mb + ' MB') : '系统 CPU / 内存占用'), hero: true, attrs: { 'data-status-card': 'resources' } }),
					infoCard({ title: '配置文件', value: status.config_name || String(status.config_count || 0), valueClass: 'is-compact', footer: status.config_updated_at ? ('最近更新 ' + status.config_updated_at) : (status.openclash_config ? '已检测到 OpenClash 配置文件' : '还没有检测到 OpenClash 配置文件'), hero: true, attrs: { 'data-status-card': 'config' } })
				]),
				E('div', { 'class': 'oca-advanced-only' }, [
					dataTable([
						E('tr', [ E('td', '服务已启用'), E('td', yesNo(status.enabled)) ]),
						E('tr', [ E('td', '已检测到 OpenClash 配置'), E('td', yesNo(status.openclash_config)) ]),
						E('tr', [ E('td', '当前运行模式'), E('td', status.current_mode || '-') ]),
						E('tr', [ E('td', '当前默认分组'), E('td', status.current_group || '-') ]),
						E('tr', [ E('td', '当前默认节点'), E('td', status.current_node || '-') ]),
						E('tr', [ E('td', '节点延迟'), E('td', status.current_node_delay ? (status.current_node_delay + ' ms') : '-') ]),
						E('tr', [ E('td', '出口地区 / 机房'), E('td', ((status.exit_country || '-') + (status.exit_colo ? (' / ' + status.exit_colo) : ''))) ]),
						E('tr', [ E('td', '出口 IP'), E('td', status.exit_ip || '-') ]),
						E('tr', [ E('td', 'CPU / 内存'), E('td', (status.cpu_pct || '-') + '% / ' + (status.mem_pct || '-') + '%') ]),
						E('tr', [ E('td', 'Clash 内存'), E('td', status.clash_mem_mb ? (status.clash_mem_mb + ' MB') : '-') ]),
						E('tr', [ E('td', '最近检测时间'), E('td', status.last_probe_at || '-') ]),
						E('tr', [ E('td', '最近错误数'), E('td', status.recent_error_count || '0') ]),
						E('tr', [ E('td', '支持 TUN 模式'), E('td', yesNo(status.tun)) ]),
						E('tr', [ E('td', '已安装 nftables'), E('td', yesNo(status.nft)) ]),
						E('tr', [ E('td', '支持 Firewall4'), E('td', yesNo(status.firewall4)) ]),
						E('tr', [ E('td', '支持 ipset'), E('td', yesNo(status.ipset)) ]),
						E('tr', [ E('td', '当前配置文件'), E('td', status.config_path || '-') ]),
						E('tr', [ E('td', '最近配置更新时间'), E('td', status.config_updated_at || '-') ]),
						E('tr', [ E('td', 'DNS 服务链路'), E('td', status.dns_chain || '-') ]),
						E('tr', [ E('td', 'DNS 诊断摘要'), E('td', status.dns_diag_summary || '-') ]),
						E('tr', [ E('td', 'DNS 建议动作'), E('td', status.dns_diag_action || '-') ])
					])
				])
			]);

			var adviceCards = E('div', { 'class': 'cbi-section oca-panel' }, [
				E('h3', '智能建议'),
				E('p', [
					badge(advice.profile || '未生成方案', riskTone(advice.risk)),
					badge(checkLevelLabel(adviceOverallLevel), checkLevelTone(adviceOverallLevel)),
					badge((adviceActionableCount > 0 ? ('待处理 ' + adviceActionableCount + ' 条') : '当前无待处理项'), adviceActionableCount > 0 ? 'warn' : 'good')
				]),
				subtleText(advice.summary || advice.why || '助手会根据当前运行状态、网站走向、流媒体、AI 和 DNS 结果，给出更贴近当前情况的建议。'),
				E('div', { 'class': 'oca-checkup-list' }, adviceItems.length ? adviceItems.map(function(item) {
					var actionNode = makeActionForItem(item);
					return E('div', { 'class': 'oca-checkup-item' }, [
						E('div', { 'class': 'oca-checkup-head' }, [
							E('div', { 'class': 'oca-checkup-title' }, item.title),
							badge(checkLevelLabel(item.level), checkLevelTone(item.level))
						]),
						E('div', { 'class': 'oca-checkup-text' }, item.text || '-'),
						E('div', { 'class': 'oca-checkup-next' }, '下一步：' + (item.next || '按当前推荐配置继续使用。')),
						actionNode ? E('div', null, [ actionNode ]) : E('div')
					]);
				}) : [
					E('div', { 'class': 'oca-checkup-item' }, [
						E('div', { 'class': 'oca-checkup-head' }, [
							E('div', { 'class': 'oca-checkup-title' }, '当前没有额外建议'),
							badge('正常', 'good')
						]),
						E('div', { 'class': 'oca-checkup-text' }, '基础运行、DNS 和专项检测暂时没有明显异常，可以继续按当前方案使用。'),
						E('div', { 'class': 'oca-checkup-next' }, '下一步：如果你还想继续优化，优先看网站走向和专项检测结果。')
					])
				]),
				E('h4', '为什么这样推荐'),
				E('div', { 'class': 'oca-link-list' }, [
					E('div', { 'class': 'oca-link-item' }, [
						E('div', null, [
							E('div', { 'class': 'oca-link-title' }, '推荐依据'),
							E('div', { 'class': 'oca-link-copy' }, advice.why || '-')
						])
					]),
					E('div', { 'class': 'oca-link-item' }, [
						E('div', null, [
							E('div', { 'class': 'oca-link-title' }, '需要留意'),
							E('div', { 'class': 'oca-link-copy' }, advice.pitfalls || '-')
						])
					]),
					E('div', { 'class': 'oca-link-item' }, [
						E('div', null, [
							E('div', { 'class': 'oca-link-title' }, '排查顺序'),
							E('div', { 'class': 'oca-link-copy' }, advice.checklist || '-')
						])
					])
				]),
				E('div', { 'class': 'oca-advanced-only' }, [
					dataTable([
						E('tr', [ E('td', '方案'), E('td', advice.profile || '-') ]),
						E('tr', [ E('td', '建议等级'), E('td', checkLevelLabel(adviceOverallLevel)) ]),
						E('tr', [ E('td', '风险'), E('td', zhRisk(advice.risk)) ]),
						E('tr', [ E('td', '建议条数'), E('td', String(advice.item_count || adviceItems.length || 0)) ]),
						E('tr', [ E('td', '推荐依据'), E('td', advice.why || '-') ]),
						E('tr', [ E('td', '常见风险'), E('td', advice.pitfalls || '-') ]),
						E('tr', [ E('td', '下一步检查清单'), E('td', advice.checklist || '-') ])
					])
				])
			]);

			var recommendationCards = E('div', { 'class': 'cbi-section oca-panel' }, [
				E('h3', '助手推荐配置'),
				E('p', [
					badge(advice.config_tier || '均衡配置', riskTone(advice.risk)),
					badge('DNS 建议', 'good'),
					badge('自动切换建议', autoSwitch.enabled ? 'good' : 'warn')
				]),
				subtleText('这里把“小白最该关心”的基础配置建议直接说人话，不需要先懂 YAML、规则组和 DNS 术语。'),
				actionButton('一键应用这套推荐', function() {
					runAction('apply-recommended-profile').then(function() {
						window.setTimeout(function() { window.location.reload(); }, 800);
					}).catch(function() {});
				}, 'secondary'),
				E('div', { 'class': 'oca-recommend-list' }, [
					makeRecommendationItem('推荐档位', advice.config_tier || '均衡配置', advice.why || '-'),
					makeRecommendationItem('DNS 建议', advice.dns_plan || '-', '先保证网站稳定打开，再决定要不要更激进。'),
					makeRecommendationItem('运行模式', advice.runtime_plan || '-', '优先保证兼容和稳定。'),
					makeRecommendationItem('日志级别', advice.log_level_plan || '-', '日志够看就行，不要默认堆太多噪音。'),
					makeRecommendationItem('自动更新', advice.auto_update_plan || '-', '更新太频繁反而容易增加不确定性。'),
					makeRecommendationItem('默认策略', advice.default_policy_plan || '-', '先把国内、国际、AI、流媒体分清，再考虑更细分。'),
					makeRecommendationItem('测速周期', advice.test_cycle_plan || '-', '检测太频繁容易切来切去。'),
					makeRecommendationItem('节点切换', advice.switch_plan || '-', '自动切换要温和、可解释。')
				]),
				E('div', { 'class': 'oca-advanced-only' }, [
					dataTable([
						E('tr', [ E('td', '推荐档位'), E('td', advice.config_tier || '-') ]),
						E('tr', [ E('td', 'DNS 建议'), E('td', advice.dns_plan || '-') ]),
						E('tr', [ E('td', '运行模式建议'), E('td', advice.runtime_plan || '-') ]),
						E('tr', [ E('td', '日志级别建议'), E('td', advice.log_level_plan || '-') ]),
						E('tr', [ E('td', '自动更新建议'), E('td', advice.auto_update_plan || '-') ]),
						E('tr', [ E('td', '默认策略建议'), E('td', advice.default_policy_plan || '-') ]),
						E('tr', [ E('td', '测速周期建议'), E('td', advice.test_cycle_plan || '-') ]),
						E('tr', [ E('td', '节点切换建议'), E('td', advice.switch_plan || '-') ])
					])
				])
			]);

			var scenarioSummaryCards = E('div', { 'class': 'cbi-section oca-panel oca-simple-only' }, [
				E('h3', '当前场景摘要'),
				E('p', [
					badge(simpleRoleLabel(status.routing_role), 'good'),
					badge(simpleModeLabel(status.preferred_mode), 'warn'),
					badge(advice.config_tier || '均衡配置', riskTone(advice.risk))
				]),
				subtleText('这里把你当前的基础场景、推荐档位和自动切换目标压缩成一句话，方便装机和售后快速确认。'),
				E('div', { 'class': 'oca-scene-list' }, [
					E('div', { 'class': 'oca-scene-item' }, [
						E('div', { 'class': 'oca-scene-title' }, '当前接入方式'),
						E('div', { 'class': 'oca-scene-copy' }, simpleRoleLabel(status.routing_role) + '，推荐按“' + (advice.profile || '均衡方案') + '”思路继续配置。')
					]),
					E('div', { 'class': 'oca-scene-item' }, [
						E('div', { 'class': 'oca-scene-title' }, '当前使用倾向'),
						E('div', { 'class': 'oca-scene-copy' }, '当前更偏“' + simpleModeLabel(status.preferred_mode) + '”。' + (advice.runtime_plan || '建议先保证兼容和稳定。'))
					]),
					E('div', { 'class': 'oca-scene-item' }, [
						E('div', { 'class': 'oca-scene-title' }, '推荐配置档位'),
						E('div', { 'class': 'oca-scene-copy' }, (advice.config_tier || '均衡配置') + '，' + (advice.dns_plan || '先保证网站稳定打开。'))
					]),
					E('div', { 'class': 'oca-scene-item' }, [
						E('div', { 'class': 'oca-scene-title' }, '自动切换目标'),
						E('div', { 'class': 'oca-scene-copy' }, (autoSwitch.goal_label || autoGoalLabel(autoSwitch.goal)) + '，范围 ' + (autoSwitch.scope_label || autoScopeLabel(autoSwitch.scope)) + '，周期 ' + String(autoSwitch.interval || '-') + ' 分钟。')
					])
				])
			]);

			var subHistoryCards = E('div', { 'class': 'cbi-section oca-panel' }, [
				E('h3', '历史订阅记录'),
				E('p', [
					badge(subconvert.history_label || '还没有历史订阅', (subconvert.history_count || 0) > 0 ? 'good' : 'warn'),
					badge('同步现有 OpenClash 参数', 'warn')
				]),
				subtleText((subconvert.history_count || 0) > 0
					? '这里列出当前 OpenClash 已识别到的订阅记录，方便售后和装机时快速核对。'
					: '当前还没有识别到历史订阅。如果你以前已经在 OpenClash 里配置过订阅，可以先试试同步按钮。'),
				E('div', { 'class': 'oca-link-list' }, (subHistory.length ? subHistory.slice(0, 6) : [ null ]).map(function(item) {
					if (!item) {
						return E('div', { 'class': 'oca-link-item' }, [
							E('div', null, [
								E('div', { 'class': 'oca-link-title' }, '暂无历史订阅'),
								E('div', { 'class': 'oca-link-copy' }, '你可以先点击“导入现有 OpenClash 订阅参数”，或者直接填写新的原始订阅。')
							])
						]);
					}

					var copy = (item.address || '未记录地址');
					copy += (item.sub_convert === '1' ? ' · 已启用转换' : ' · 未启用转换');
					if (item.template)
						copy += ' · 模板 ' + item.template;

					return E('div', { 'class': 'oca-link-item' }, [
						E('div', null, [
							E('div', { 'class': 'oca-link-title' }, item.name || '未命名订阅'),
							E('div', { 'class': 'oca-link-copy' }, copy)
						]),
						E('div', null, [
							badge(item.enabled === '1' ? '已启用' : '未启用', item.enabled === '1' ? 'good' : 'warn'),
							actionButton('导入这条', function() {
								fs.exec('/usr/libexec/openclash-assistant/diag.sh', [ 'sync-subconvert-section-from-openclash', item.sid || '' ]).then(function(res) {
									var result = safeParse(res.stdout || '{}', {});
									window.alert(result.message || '执行完成');
									window.setTimeout(function() { window.location.reload(); }, 800);
								}).catch(function(err) {
									window.alert('执行失败：' + err);
								});
							}, 'ghost')
						])
					]);
				})),
				actionButton('导入现有 OpenClash 订阅参数', function() {
					runAction('sync-subconvert-from-openclash');
				}, 'ghost')
			]);

			var subWorkflowCards = E('div', { 'class': 'cbi-section oca-panel' }, [
				E('h3', '订阅导入与转换'),
				E('p', [
					(function() {
						var node = badge(subconvert.source ? '已填写原始订阅' : '等待填写订阅', subconvert.source ? 'good' : 'warn');
						node.setAttribute('data-subconvert-badge', 'source');
						return node;
					})(),
					(function() {
						var node = badge(subconvert.template_name || '模板待确认', subconvert.template_name ? 'good' : 'warn');
						node.setAttribute('data-subconvert-badge', 'template');
						return node;
					})(),
					(function() {
						var node = badge(subconvert.backend_ready ? '转换后端正常' : '转换后端待检查', subconvert.backend_ready ? 'good' : 'warn');
						node.setAttribute('data-subconvert-badge', 'backend');
						return node;
					})()
				]),
				E('p', { 'class': 'oca-subtle', 'data-subconvert-next-step': '1' }, subconvert.next_step || '在这个页面完成原始订阅填写、转换预览和一键导入。'),
				E('div', { 'class': 'oca-summary-card oca-simple-only', 'style': 'margin-bottom:16px;' }, [
					E('div', { 'class': 'oca-summary-eyebrow' }, '单页流程'),
					E('div', { 'class': 'oca-summary-title' }, '填原始订阅，预览转换，直接导入'),
					E('p', { 'class': 'oca-summary-copy' }, '先在上方填写原始订阅地址和模板。保存后，这里会直接带出转换预览。确认没问题后，点击“一键导入 OpenClash”即可。')
				]),
				E('div', { 'class': 'oca-grid' }, [
					infoCard({
						title: '原始订阅',
						value: subconvert.source ? (subconvert.source_valid ? '已填写' : '格式异常') : '待填写',
						footer: subconvert.source_status_text || '先填写原始订阅地址。',
						hero: true,
						attrs: { 'data-subconvert-card': 'source' }
					}),
					infoCard({
						title: '当前模板',
						value: subconvert.template_name || '未设置',
						valueClass: 'is-compact',
						footer: subconvert.template_status_text || '先确认模板是否匹配。',
						hero: true,
						attrs: { 'data-subconvert-card': 'template' }
					}),
					infoCard({
						title: '转换后端',
						value: subconvert.backend_ready ? '已连通' : '待确认',
						footer: subconvert.backend_status_text || '默认建议保持当前转换后端。',
						hero: true,
						attrs: { 'data-subconvert-card': 'backend' }
					}),
					infoCard({
						title: '导入后基础走向',
						value: subconvert.expected_groups_text || '国内直连、国际常用、AI、流媒体',
						valueClass: 'is-compact',
						footer: subconvert.expected_ai || 'AI 服务建议单独走 AI 或国际稳定分组。',
						hero: true,
						attrs: { 'data-subconvert-card': 'groups' }
					})
				]),
				E('div', { 'class': 'oca-link-list' }, [
						E('div', { 'class': 'oca-link-item' }, [
							E('div', null, [
								E('div', { 'class': 'oca-link-title' }, '转换说明'),
								E('div', { 'class': 'oca-link-copy', 'data-subconvert-copy': 'convert' }, subconvert.should_convert_text || '建议先转换再导入。')
							])
						]),
						E('div', { 'class': 'oca-link-item' }, [
							E('div', null, [
								E('div', { 'class': 'oca-link-title' }, '推荐模板'),
								E('div', { 'class': 'oca-link-copy', 'data-subconvert-copy': 'template' }, (subconvert.recommended_template_name || '未匹配') + '。如果你不确定，优先用推荐模板。')
							])
						]),
						E('div', { 'class': 'oca-link-item' }, [
							E('div', null, [
								E('div', { 'class': 'oca-link-title' }, '导入后怎么走'),
								E('div', { 'class': 'oca-link-copy', 'data-subconvert-copy': 'flow' }, subconvert.expected_domestic || '国内默认直连，国际、AI、流媒体按分组处理。')
							])
						])
				]),
				E('div', null, [
					actionButton('导入现有 OpenClash 订阅参数', function() {
						runAction('sync-subconvert-from-openclash');
					}, 'ghost'),
					actionButton('打开转换预览', function() {
						ensureSubconvertPreviewLoaded();
					}, 'secondary'),
					actionButton('在新窗口打开', function() {
						window.open(embeddedFrontendUrl, '_blank');
					}, 'ghost'),
					actionButton('一键导入 OpenClash', function() {
						runAction('apply-subconvert');
					})
				]),
				(subconvertPreviewWrap = E('div', {
					'class': 'oca-frame',
					'data-preview-loaded': '0'
				}, [
					callout('点击“打开转换预览”后，这里会加载本地转换页面。确认结果没问题后，直接点“一键导入 OpenClash”。', 'info')
				])),
				E('div', { 'class': 'oca-advanced-only' }, [
					dataTable([
						E('tr', [ E('td', '原始订阅状态'), E('td', subconvert.source_status_text || '-') ]),
						E('tr', [ E('td', '内容探测'), E('td', subconvert.source_detected_as || '-') ]),
						E('tr', [ E('td', '后端状态'), E('td', subconvert.backend_status_text || '-') ]),
						E('tr', [ E('td', '模板状态'), E('td', subconvert.template_status_text || '-') ]),
						E('tr', [ E('td', '导入说明'), E('td', subconvert.next_step || '-') ])
					]),
					preBlock(embeddedFrontendUrl),
					preBlock(subconvert.convert_url || '请先填写原始订阅地址，再保存页面。')
				])
			]);

			var dnsCards = E('div', { 'class': 'cbi-section oca-panel' }, [
				E('h3', 'DNS 检测与修复'),
				E('p', [
					badge(flushDns.dns_diag_level === 'good' ? '解析基本正常' : '解析需要修一下', flushDns.dns_diag_level === 'good' ? 'good' : 'warn'),
					badge(flushDns.openclash_running ? 'OpenClash 已运行' : 'OpenClash 未运行', flushDns.openclash_running ? 'good' : 'warn'),
					badge(flushDns.dnsmasq_running ? 'dnsmasq 正常' : 'dnsmasq 未运行', flushDns.dnsmasq_running ? 'good' : 'warn')
				]),
				subtleText(flushDns.dns_diag_summary || '当前还没有拿到完整的解析状态。'),
				E('div', { 'class': 'oca-grid' }, [
					infoCard({
						title: '最近刷新时间',
						value: flushDns.last_run_at || '暂无',
						footer: '最近一次执行时间',
						valueField: 'last-run-value',
						attrs: { 'data-dns-card': 'last-run' }
					}),
					infoCard({
						title: '刷新结果',
						value: flushDns.last_message || '暂无',
						valueClass: 'is-compact',
						footer: flushDns.hint || '-',
						valueField: 'last-message-value',
						attrs: { 'data-dns-card': 'last-message' }
					}),
					infoCard({
						title: '当前解析链路',
						value: flushDns.dns_chain || '-',
						valueClass: 'is-compact',
						footer: flushDns.dns_diag_summary || '-',
						valueField: 'chain-value',
						attrs: { 'data-dns-card': 'chain' }
					}),
					infoCard({
						title: '建议动作',
						value: flushDns.dns_diag_action || '-',
						valueClass: 'is-compact',
						footer: '修复后建议重新检测',
						valueField: 'action-value',
						attrs: { 'data-dns-card': 'action' }
					})
				]),
				actionButton('一键刷新解析', function() {
					runAction('flush-dns').then(function() {
						return fs.exec('/usr/libexec/openclash-assistant/diag.sh', [ 'flush-dns-json' ]);
					}).then(function(res) {
						var nextFlushDns = safeParse(res.stdout || '{}', {});
						var cards = dnsCards.querySelectorAll('[data-dns-card]');
						if (cards[0]) cards[0].querySelector('.oca-card-value').textContent = nextFlushDns.last_run_at || '暂无';
						if (cards[1]) {
							cards[1].querySelector('.oca-card-value').textContent = nextFlushDns.last_message || '暂无';
							cards[1].querySelector('.oca-card-footer').textContent = nextFlushDns.hint || '-';
						}
						if (cards[2]) {
							cards[2].querySelector('.oca-card-value').textContent = nextFlushDns.dns_chain || '-';
							cards[2].querySelector('.oca-card-footer').textContent = nextFlushDns.dns_diag_summary || '-';
						}
						if (cards[3])
							cards[3].querySelector('.oca-card-value').textContent = nextFlushDns.dns_diag_action || '-';
					}).catch(function() {});
				}),
				E('div', { 'class': 'oca-advanced-only' }, [
					dataTable([
						E('tr', [ E('td', 'smartdns 已安装'), E('td', yesNo(flushDns.smartdns_available)) ]),
						E('tr', [ E('td', 'smartdns 正在运行'), E('td', yesNo(flushDns.smartdns_running)) ]),
						E('tr', [ E('td', '诊断等级'), E('td', flushDns.dns_diag_level || '-') ])
					])
				])
			]);

			var splitPrimaryTargets = sortSplitTunnelTargets(splitTunnelTargets.filter(function(item) {
				return splitTunnelPrimaryTargets.indexOf(item.key) >= 0;
			}), splitTunnel);
			var splitSecondaryTargets = sortSplitTunnelTargets(splitTunnelTargets.filter(function(item) {
				return splitTunnelPrimaryTargets.indexOf(item.key) < 0;
			}), splitTunnel);

			var splitTunnelCards = E('div', { 'class': 'cbi-section oca-panel' }, [
				E('h3', '网站走向检测'),
				E('p', [
					badge(splitTunnel.test_running ? '检测进行中' : '检测空闲', splitTunnel.test_running ? 'warn' : 'good'),
					badge('正常 ' + String(splitTunnel.success_count || 0), (splitTunnel.success_count || 0) > 0 ? 'good' : 'warn'),
					badge('异常 ' + String(splitTunnel.issue_count || 0), (splitTunnel.issue_count || 0) > 0 ? 'bad' : 'good')
				]),
				subtleText(splitTunnel.summary || '这里会告诉你网站最后走了哪条路、从哪里出去。'),
				actionButton('重新跑网站走向检测', function() {
					triggerSplitChecks(true);
				}, 'secondary'),
				E('h4', '核心目标'),
				subtleText('先看最常见、最值得判断的网站出口。'),
				makeSplitTunnelCards(splitPrimaryTargets),
				E('div', { 'class': 'oca-advanced-only' }, [
					E('h4', { 'style': 'margin-top:16px;' }, '补充目标'),
					subtleText('这些目标用于补充判断，不一定都会稳定返回出口信息。'),
					makeSplitTunnelCards(splitSecondaryTargets),
					dataTable([
						E('tr', [ E('td', '最近一次检查'), E('td', { 'data-split-summary': 'last_run_at' }, splitTunnel.last_run_at || '暂无') ]),
						E('tr', [ E('td', '说明'), E('td', { 'data-split-summary': 'summary' }, splitTunnel.summary || '-') ])
					])
				])
			]);

			var routeTestInput = E('input', {
				'class': 'oca-route-input',
				'type': 'text',
				'placeholder': '例如：ChatGPT / openai.com / https://www.youtube.com/',
				'value': readCachedJson('openclash-assistant-route-input-cache', { value: '' }).value || ''
			});
			var routeTestResultWrap = E('div', { 'class': 'oca-route-result' }, [
				callout('支持输入服务名、域名或完整网址。结果会尽量告诉你它命中了哪条规则、走了哪个分组，以及下一步该怎么改。', 'info')
			]);

			var runRouteTest = function(value) {
				var input = (value || routeTestInput.value || '').trim();
				if (!input) {
					routeTestResultWrap.innerHTML = '';
					routeTestResultWrap.appendChild(callout('请输入域名、网址，或者服务名再开始检测。', 'warn'));
					return;
				}

				routeTestInput.value = input;
				writeCachedJson('openclash-assistant-route-input-cache', { value: input });
				routeTestResultWrap.innerHTML = '';
				routeTestResultWrap.appendChild(callout('正在检测这个网站现在到底走哪条路，请稍等几秒。', 'info'));

				fs.exec('/usr/libexec/openclash-assistant/diag.sh', [ 'split-route-test-json', input ]).then(function(res) {
					var result = safeParse(res.stdout || '{}', {});
					routeTestResultWrap.innerHTML = '';
					routeTestResultWrap.appendChild(renderRouteTestResult(result));
				}).catch(function(err) {
					routeTestResultWrap.innerHTML = '';
					routeTestResultWrap.appendChild(callout('检测失败：' + err, 'warn'));
				});
			};

			var customRouteCards = E('div', { 'class': 'cbi-section oca-panel' }, [
				E('h3', '单个网站走向检测'),
				E('p', [
					badge('支持服务名 / 域名 / URL', 'good'),
					badge('结果尽量说人话', 'warn')
				]),
				subtleText('这里适合回答最常见的问题：这个网站为什么打不开，它现在到底走直连还是代理？'),
				E('div', { 'class': 'oca-route-form' }, [
					E('div', { 'class': 'oca-route-field' }, [
						E('label', { 'class': 'oca-route-label' }, '输入你要检测的网站或服务'),
						routeTestInput
					]),
					actionButton('开始检测', function() {
						runRouteTest(routeTestInput.value);
					})
				]),
				E('div', { 'class': 'oca-preset-bar' }, [
					'ChatGPT', 'OpenAI', 'Claude', 'Gemini', 'Netflix', 'YouTube', 'Bilibili', 'Discord'
				].map(function(item) {
					return E('button', {
						'class': 'btn cbi-button oca-preset',
						'click': function(ev) {
							ev.preventDefault();
							runRouteTest(item);
						}
					}, [ item ]);
				})),
				routeTestResultWrap
			]);

			var streamingCards = E('div', { 'class': 'cbi-section oca-panel' }, [
				E('h3', '流媒体检测'),
				E('p', [
					badge(mediaAi.test_running ? '后台检测中' : '检测空闲', mediaAi.test_running ? 'warn' : 'good'),
					badge('可用 ' + String(streamingSuccessCount), streamingSuccessCount > 0 ? 'good' : 'warn'),
					badge('异常 ' + String(streamingIssueCount), streamingIssueCount > 0 ? 'bad' : 'good')
				]),
				subtleText(mediaAi.summary || '用于判断 Netflix、Disney+、YouTube Premium 等服务是否适合当前线路。'),
				actionButton('重新跑流媒体检测', function() {
					triggerMediaChecks(true);
				}, 'secondary'),
				E('div', { 'class': 'oca-link-list' }, streamingTargets.slice(0, 5).map(function(item) {
					var streamingBadge = badge(mediaAi[item.key + '_status_text'] || '暂无结果', mediaAi[item.key + '_tone'] || 'warn');
					streamingBadge.setAttribute('data-media-link-badge', item.key);
					return E('div', { 'class': 'oca-link-item' }, [
						E('div', null, [
							E('div', { 'class': 'oca-link-title' }, [
								item.label + '：',
								E('span', { 'data-media-link-title': item.key }, mediaAi[item.key + '_long_term_fit'] || streamingLongTermLabel(item.key, mediaAi))
							]),
							E('div', { 'class': 'oca-link-copy', 'data-media-link-copy': item.key }, (mediaAi[item.key + '_diagnosis'] || streamingServiceAdvice(item.key, mediaAi)) + ' ' + (mediaAi[item.key + '_next_step'] || ''))
						]),
						streamingBadge
					]);
				})),
				makeMediaResultCards(streamingTargets),
				E('div', { 'class': 'oca-advanced-only' }, [
					dataTable([
						E('tr', [ E('td', '最近一次检查'), E('td', { 'data-summary-field': 'last_run_at' }, mediaAi.last_run_at || '暂无') ]),
						E('tr', [ E('td', '检测说明'), E('td', { 'data-summary-field': 'summary' }, mediaAi.summary || '-') ]),
						E('tr', [ E('td', '建议'), E('td', { 'data-summary-field': 'suggestion' }, mediaAi.suggestion || '-') ])
					])
				])
			]);

			var aiCards = E('div', { 'class': 'cbi-section oca-panel' }, [
				E('h3', 'AI 服务测试'),
				E('p', [
					badge(mediaAi.test_running ? '后台检测中' : '检测空闲', mediaAi.test_running ? 'warn' : 'good'),
					badge('可访问 ' + String(aiSuccessCount), aiSuccessCount > 0 ? 'good' : 'warn'),
					badge('异常 ' + String(aiIssueCount), aiIssueCount > 0 ? 'bad' : 'good')
				]),
				subtleText(aiIssueCount > 0
					? '当前有 AI 服务访问不稳定，建议优先看地区和线路是否适合。'
					: '这里会告诉你 ChatGPT、Claude、Gemini 等服务当前是否适合使用。'),
				actionButton('重新跑 AI 检测', function() {
					triggerMediaChecks(true);
				}, 'secondary'),
				E('div', { 'class': 'oca-link-list' }, aiTargets.map(function(item) {
					var aiBadge = badge(mediaAi[item.key + '_status_text'] || '暂无结果', mediaAi[item.key + '_tone'] || 'warn');
					aiBadge.setAttribute('data-media-link-badge', item.key);
					return E('div', { 'class': 'oca-link-item' }, [
						E('div', null, [
							E('div', { 'class': 'oca-link-title' }, [
								item.label + '：',
								E('span', { 'data-media-link-title': item.key }, mediaAi[item.key + '_risk_hint'] || aiServicePurpose(item.key))
							]),
							E('div', { 'class': 'oca-link-copy', 'data-media-link-copy': item.key }, (mediaAi[item.key + '_diagnosis'] || aiServiceAdvice(item.key, mediaAi)) + ' 建议地区：' + (mediaAi[item.key + '_recommended_region'] || aiServiceRegionHint(item.key)))
						]),
						aiBadge
					]);
				})),
				makeMediaResultCards(aiTargets),
				E('div', { 'class': 'oca-advanced-only' }, [
					dataTable([
						E('tr', [ E('td', '最近一次检查'), E('td', { 'data-summary-field': 'last_run_at' }, mediaAi.last_run_at || '暂无') ]),
						E('tr', [ E('td', 'ChatGPT / OpenAI'), E('td', (mediaAi.openai_status_text || '暂无结果') + (mediaAi.openai_latency_ms ? (' / ' + mediaAi.openai_latency_ms + ' ms') : '')) ]),
						E('tr', [ E('td', 'Claude'), E('td', (mediaAi.claude_status_text || '暂无结果') + (mediaAi.claude_latency_ms ? (' / ' + mediaAi.claude_latency_ms + ' ms') : '')) ]),
						E('tr', [ E('td', 'Gemini'), E('td', (mediaAi.gemini_status_text || '暂无结果') + (mediaAi.gemini_latency_ms ? (' / ' + mediaAi.gemini_latency_ms + ' ms') : '')) ]),
						E('tr', [ E('td', 'Grok'), E('td', (mediaAi.grok_status_text || '暂无结果') + (mediaAi.grok_latency_ms ? (' / ' + mediaAi.grok_latency_ms + ' ms') : '')) ]),
						E('tr', [ E('td', 'Perplexity'), E('td', (mediaAi.perplexity_status_text || '暂无结果') + (mediaAi.perplexity_latency_ms ? (' / ' + mediaAi.perplexity_latency_ms + ' ms') : '')) ]),
						E('tr', [ E('td', 'Poe'), E('td', (mediaAi.poe_status_text || '暂无结果') + (mediaAi.poe_latency_ms ? (' / ' + mediaAi.poe_latency_ms + ' ms') : '')) ]),
						E('tr', [ E('td', 'Cursor'), E('td', (mediaAi.cursor_status_text || '暂无结果') + (mediaAi.cursor_latency_ms ? (' / ' + mediaAi.cursor_latency_ms + ' ms') : '')) ]),
						E('tr', [ E('td', 'Codex / API'), E('td', (mediaAi.codex_status_text || '暂无结果') + (mediaAi.codex_latency_ms ? (' / ' + mediaAi.codex_latency_ms + ' ms') : '')) ])
					])
				])
			]);

			var switchCards = E('div', { 'class': 'cbi-section oca-panel' }, [
				E('h3', '自动切换建议'),
				E('p', [
					badge(autoSwitch.enabled ? '建议开启自动切换' : '当前可保持手动', autoSwitch.enabled ? 'good' : 'warn'),
					badge('目标：' + (autoSwitch.goal_label || autoGoalLabel(autoSwitch.goal)), 'warn'),
					badge('范围：' + (autoSwitch.scope_label || autoScopeLabel(autoSwitch.scope)), 'good'),
					badge(status.stream_auto_select === '1' ? 'OpenClash 已开启' : 'OpenClash 未开启', status.stream_auto_select === '1' ? 'good' : 'warn')
				]),
				subtleText(autoSwitch.suggestion || '如果你节点较多，自动切换通常更省心。'),
				E('h4', '当前节点画像'),
				E('div', { 'class': 'oca-grid' }, [
					infoCard({
						title: '当前节点',
						value: autoSwitch.current_node || status.current_node || '暂未识别',
						valueClass: 'is-compact',
						footer: autoSwitch.current_delay ? ('最近延迟 ' + autoSwitch.current_delay + ' ms') : '还没有拿到当前延迟',
						hero: true
					}),
					infoCard({
						title: '更适合什么',
						value: autoSwitch.node_best_for || '日常浏览',
						footer: autoSwitch.node_profile_title || '当前节点画像',
						hero: true
					}),
					infoCard({
						title: 'AI / 流媒体',
						value: (autoSwitch.node_ai_fit || '可临时使用') + ' / ' + (autoSwitch.node_streaming_fit || '可临时使用'),
						footer: '前者是 AI，后者是流媒体。',
						hero: true
					}),
					infoCard({
						title: '低延迟 / 长期用',
						value: (autoSwitch.node_game_fit || '不建议') + ' / ' + (autoSwitch.node_long_term_fit || '可继续观察'),
						footer: '前者偏游戏和实时场景，后者偏长期主力。',
						hero: true
					})
				]),
				E('div', { 'class': 'oca-link-list' }, [
					E('div', { 'class': 'oca-link-item' }, [
						E('div', null, [
							E('div', { 'class': 'oca-link-title' }, autoSwitch.node_profile_title || '当前节点画像'),
							E('div', { 'class': 'oca-link-copy' }, autoSwitch.node_profile_summary || '助手会根据延迟、流媒体和 AI 结果判断当前节点更适合什么用途。')
						])
					]),
					E('div', { 'class': 'oca-link-item' }, [
						E('div', null, [
							E('div', { 'class': 'oca-link-title' }, '为什么建议切或不切'),
							E('div', { 'class': 'oca-link-copy' }, autoSwitch.node_switch_reason || '如果当前没有明显问题，可以先保持当前节点。')
						])
					]),
					E('div', { 'class': 'oca-link-item' }, [
						E('div', null, [
							E('div', { 'class': 'oca-link-title' }, '下一步怎么做'),
							E('div', { 'class': 'oca-link-copy' }, autoSwitch.node_next_step || '继续观察专项检测结果，再决定是否切换。')
						])
					])
				]),
				E('div', { 'class': 'oca-grid' }, [
					infoCard({
						title: '目标优先',
						value: autoSwitch.goal_label || autoGoalLabel(autoSwitch.goal),
						footer: autoSwitch.goal_hint || '建议按实际用途选择目标优先级。',
						hero: true
					}),
					infoCard({
						title: '切换范围',
						value: autoSwitch.scope_label || autoScopeLabel(autoSwitch.scope),
						footer: autoSwitch.scope_hint || '范围越大，越容易切到不适合当前用途的线路。',
						hero: true
					}),
					infoCard({
						title: '触发条件',
						value: String(autoSwitch.interval || '-') + ' 分钟',
						footer: autoSwitch.threshold_hint || '建议结合延迟、丢包和失败次数综合判断。',
						hero: true
					}),
					infoCard({
						title: '恢复策略',
						value: autoSwitch.revert_label || (autoSwitch.revert_preferred ? '允许回切首选节点' : '保持当前优选结果'),
						footer: autoSwitch.close_con ? '切换后会尽量清理旧连接。' : '切换后会尽量保留旧连接。',
						hero: true
					})
				]),
				E('div', { 'class': 'oca-link-list' }, [
					E('div', { 'class': 'oca-link-item' }, [
						E('div', null, [
							E('div', { 'class': 'oca-link-title' }, autoSwitch.recommendation_title || '自动切换方案'),
							E('div', { 'class': 'oca-link-copy' }, autoSwitch.goal_hint || '优先解决节点忽好忽坏、需要频繁手动切换的问题。')
						])
					]),
					E('div', { 'class': 'oca-link-item' }, [
						E('div', null, [
							E('div', { 'class': 'oca-link-title' }, '什么时候会切'),
							E('div', { 'class': 'oca-link-copy' }, autoSwitch.threshold_hint || '当延迟、丢包或连续失败达到阈值时，会建议切换。')
						])
					]),
					E('div', { 'class': 'oca-link-item' }, [
						E('div', null, [
							E('div', { 'class': 'oca-link-title' }, '会切到哪里'),
							E('div', { 'class': 'oca-link-copy' }, autoSwitch.scope_hint || '默认先在更贴近当前用途的候选范围里切换。')
						])
					])
				]),
				actionButton('一键应用自动切换', function() {
					runAction('apply-auto-switch');
				}),
				E('div', { 'class': 'oca-advanced-only' }, [
					dataTable([
						E('tr', [ E('td', '当前节点'), E('td', autoSwitch.current_node || '-') ]),
						E('tr', [ E('td', '当前延迟'), E('td', autoSwitch.current_delay ? (String(autoSwitch.current_delay) + ' ms') : '-') ]),
						E('tr', [ E('td', '更适合什么'), E('td', autoSwitch.node_best_for || '-') ]),
						E('tr', [ E('td', 'AI 适配度'), E('td', autoSwitch.node_ai_fit || '-') ]),
						E('tr', [ E('td', '流媒体适配度'), E('td', autoSwitch.node_streaming_fit || '-') ]),
						E('tr', [ E('td', '低延迟适配度'), E('td', autoSwitch.node_game_fit || '-') ]),
						E('tr', [ E('td', '长期使用建议'), E('td', autoSwitch.node_long_term_fit || '-') ]),
						E('tr', [ E('td', '目标优先'), E('td', autoSwitch.goal_label || '-') ]),
						E('tr', [ E('td', '切换范围'), E('td', autoSwitch.scope_label || '-') ]),
						E('tr', [ E('td', '检测间隔'), E('td', String(autoSwitch.interval || '-')) ]),
						E('tr', [ E('td', '延迟阈值'), E('td', String(autoSwitch.latency_threshold || '-') + ' ms') ]),
						E('tr', [ E('td', '丢包阈值'), E('td', String(autoSwitch.packet_loss_threshold || '-') + '%') ]),
						E('tr', [ E('td', '连续失败阈值'), E('td', String(autoSwitch.fail_threshold || '-') + ' 次') ]),
						E('tr', [ E('td', '恢复策略'), E('td', autoSwitch.revert_label || '-') ]),
						E('tr', [ E('td', '当前 OpenClash 逻辑'), E('td', status.stream_auto_select_logic || '-') ]),
						E('tr', [ E('td', '当前 OpenClash 间隔'), E('td', status.stream_auto_select_interval || '-') ]),
						E('tr', [ E('td', '建议说明'), E('td', autoSwitch.suggestion || '-') ])
					]),
					preBlock(autoSwitch.commands)
				])
			]);

			var hero = E('div', { 'class': 'oca-hero' }, [
				E('div', { 'class': 'oca-hero-main' }, [
					E('div', { 'class': 'oca-topbar' }, [
						E('div', { 'class': 'oca-kicker' }, 'OpenClash 助手'),
						E('div', { 'class': 'oca-mode-switch' }, [
							E('span', { 'class': 'oca-mode-hint' }, '显示模式'),
							E('button', {
								'class': 'btn cbi-button oca-mode-chip' + (displayMode === 'simple' ? ' active' : ''),
								'data-mode-chip': 'simple',
								'click': function(ev) {
									ev.preventDefault();
									setDisplayMode('simple');
								}
							}, [ '小白模式' ]),
							E('button', {
								'class': 'btn cbi-button oca-mode-chip' + (displayMode === 'advanced' ? ' active' : ''),
								'data-mode-chip': 'advanced',
								'click': function(ev) {
									ev.preventDefault();
									setDisplayMode('advanced');
								}
							}, [ '高级模式' ])
						])
					]),
					E('div', { 'class': 'oca-hero-title' }, '先导入订阅，再按用途生成配置，最后一键检查和修复。'),
					E('p', { 'class': 'oca-hero-copy' }, '这里不是一堆杂乱按钮，而是按真实使用流程组织的助手页面。第一步处理订阅，第二步选择基础场景，第三步看体检、流媒体、AI、DNS 和网站走向结果。默认尽量说人话，高级模式再展开底层细节。')
				]),
				E('div', { 'class': 'oca-hero-side' }, [
					E('div', { 'class': 'oca-summary-card' }, [
						E('div', { 'class': 'oca-summary-eyebrow' }, '当前建议'),
						E('div', { 'class': 'oca-summary-title' }, checkLevelLabel(checkupModel.overall)),
						E('p', { 'class': 'oca-summary-copy' }, checkupModel.summary),
						E('div', { 'class': 'oca-link-list' }, checkupModel.items.slice(0, 3).map(function(item) {
							return E('div', { 'class': 'oca-link-item' }, [
								E('div', null, [
									E('div', { 'class': 'oca-link-title' }, item.title),
									E('div', { 'class': 'oca-link-copy' }, item.next)
								]),
								badge(checkLevelLabel(item.level), checkLevelTone(item.level))
							]);
						}))
					]),
					E('div', { 'class': 'oca-mini-grid' }, [
						infoCard({ title: 'OpenClash', value: status.running ? '运行中' : '未运行', footer: status.dns_diag_summary || '等待检测', hero: true, attrs: { 'data-live-card': 'hero-openclash' } }),
						infoCard({ title: '当前节点', value: status.current_node || '暂未识别', valueClass: 'is-compact', footer: status.current_node_delay ? ('延迟 ' + status.current_node_delay + ' ms') : '等待采集', hero: true, attrs: { 'data-live-card': 'hero-current-node' } }),
						infoCard({ title: '出口位置', value: status.exit_country || '-', footer: status.exit_ip || '等待采集', hero: true, attrs: { 'data-live-card': 'hero-exit' } }),
						infoCard({ title: '订阅转换', value: subconvert.template_name || '未设置', footer: subconvert.source ? '已填写原始订阅' : '等待导入订阅', hero: true, attrs: { 'data-live-card': 'hero-subconvert' } })
					])
				])
			]);

			var quickActions = E('div', { 'class': 'oca-quick-grid' }, [
				{
					kicker: '01',
					title: '一键导入订阅',
					copy: '先把原始订阅贴进来，再在本地转换页里生成适合 OpenClash 的配置。',
					label: '去导入',
					handler: function() { openTab('subconvert'); }
				},
				{
					kicker: '02',
					title: '一键转换配置',
					copy: '使用本地 subconverter 和内置 sub-web-modify，避免跳到外站。',
					label: '去转换',
					handler: function() { openTab('subconvert'); }
				},
				{
					kicker: '03',
					title: '一键推荐配置',
					copy: '按旁路由、主路由、兼容性和维护偏好生成更稳妥的建议。',
					label: '看推荐',
					handler: function() { openTab('overview'); }
				},
				{
					kicker: '04',
					title: '一键体检',
					copy: '把基础服务、订阅、解析和检测结果串起来，直接告诉你下一步怎么做。',
					label: '开始体检',
					handler: function() { runAssistantCheckup(); }
				},
				{
					kicker: '05',
					title: '一键刷新 DNS',
					copy: '网站打不开、时好时坏时，先试这个最省事。',
					label: '立即刷新',
					handler: function() { runAction('flush-dns'); }
				},
				{
					kicker: '06',
					title: '一键优选节点',
					copy: '先看网站走向、流媒体和 AI 结果，再决定哪些节点更适合长期用。',
					label: '去查看',
					handler: function() { openTab('split'); }
				}
			].map(function(item) {
				return E('div', { 'class': 'oca-quick-card' }, [
					E('div', { 'class': 'oca-quick-kicker' }, item.kicker),
					E('div', { 'class': 'oca-quick-title' }, item.title),
					E('div', { 'class': 'oca-quick-copy' }, item.copy),
					E('div', { 'class': 'oca-quick-actions' }, [
						actionButton(item.label, item.handler, 'ghost')
					])
				]);
			}));

			var formSections = Array.prototype.slice.call(node.querySelectorAll('.cbi-section'));
			formSections.forEach(function(section) {
				section.classList.add('oca-panel');
				Array.prototype.forEach.call(section.querySelectorAll('.cbi-section-table'), function(table) {
					table.classList.add('oca-table');
				});
			});
			var topologyFormSection = formSections[0] || null;
			var compatibilityFormSection = formSections[1] || null;
			var preferenceFormSection = formSections[2] || null;
			var mediaFormSection = formSections[3] || null;
			var aiFormSection = formSections[4] || null;
			var autoFormSection = formSections[5] || null;
			var subFormSection = formSections[6] || null;

			if (mediaFormSection)
				mediaFormSection.classList.add('oca-advanced-only');
			if (aiFormSection)
				aiFormSection.classList.add('oca-advanced-only');
			if (autoFormSection)
				autoFormSection.classList.add('oca-advanced-only');

			var subConvertPane = E('div', { 'data-tab-pane': 'subconvert' });
			var overviewPane = E('div', { 'data-tab-pane': 'overview' });
			var checkupPane = E('div', { 'data-tab-pane': 'checkup' });
			var streamingPane = E('div', { 'data-tab-pane': 'streaming' });
			var aiPane = E('div', { 'data-tab-pane': 'ai' });
			var dnsPane = E('div', { 'data-tab-pane': 'dns' });
			var autoPane = E('div', { 'data-tab-pane': 'auto' });
			var splitPane = E('div', { 'data-tab-pane': 'split' });

			if (subFormSection)
				subConvertPane.appendChild(subFormSection);
			subConvertPane.insertBefore(callout('这个页面直接完成订阅导入与转换：填写原始订阅地址，确认转换预览，然后一键导入 OpenClash。', 'good'), subConvertPane.firstChild || null);
			subConvertPane.appendChild(E('div', { 'class': 'oca-summary-card oca-simple-only' }, [
				E('div', { 'class': 'oca-summary-eyebrow' }, '新手流程'),
				E('div', { 'class': 'oca-summary-title' }, '原始订阅、转换预览、导入都在这一页'),
				E('p', { 'class': 'oca-summary-copy' }, '只要在上面填好原始订阅和模板，这一页就能直接看转换结果，并一键导入 OpenClash。')
			]));
			subConvertPane.appendChild(subWorkflowCards);
			subHistoryCards.classList.add('oca-advanced-only');
			subConvertPane.appendChild(subHistoryCards);

			var scenarioColumn = E('div', { 'class': 'oca-stack' });
			scenarioColumn.appendChild(scenarioSummaryCards);
			if (topologyFormSection)
				scenarioColumn.appendChild(topologyFormSection);
			if (compatibilityFormSection)
				scenarioColumn.appendChild(compatibilityFormSection);
			if (preferenceFormSection)
				scenarioColumn.appendChild(preferenceFormSection);

			var summaryColumn = E('div', { 'class': 'oca-stack' }, [
				statusCards,
				adviceCards,
				recommendationCards
			]);

			overviewPane.appendChild(callout('第二页只做一件事：根据你的使用场景生成更适合的新手配置，并把当前运行状态和基础建议放在右侧，方便边看边改。', 'info'));
			overviewPane.appendChild(E('div', { 'class': 'oca-summary-card oca-simple-only', 'style': 'margin-bottom:16px;' }, [
				E('div', { 'class': 'oca-summary-eyebrow' }, '这一页怎么用'),
				E('div', { 'class': 'oca-summary-title' }, '左边选场景，右边看状态和建议'),
				E('p', { 'class': 'oca-summary-copy' }, '如果你是旁路由、家里有游戏机、或者要远程访问家里设备，就在左边勾出来。右边会同步给出更稳妥的建议。')
			]));
			overviewPane.appendChild(E('div', { 'class': 'oca-dual' }, [ scenarioColumn, summaryColumn ]));

			checkupPane.appendChild(callout('这里把“检测结果 -> 修复建议 -> 一键动作”串起来，不需要你先去看日志。', 'warn'));
			checkupPane.appendChild(checkupCards);

			if (mediaFormSection)
				streamingPane.appendChild(mediaFormSection);
			streamingPane.insertBefore(callout('流媒体页优先告诉你能不能看、像不像长期可用的主力节点。', 'info'), streamingPane.firstChild || null);
			streamingPane.appendChild(E('div', { 'class': 'oca-summary-card oca-simple-only', 'style': 'margin-bottom:16px;' }, [
				E('div', { 'class': 'oca-summary-eyebrow' }, '看什么'),
				E('div', { 'class': 'oca-summary-title' }, '这里主要看视频平台是否适合当前节点'),
				E('p', { 'class': 'oca-summary-copy' }, '别只看能不能打开，更要看地区是不是对、结果稳不稳、适不适合长期当主力流媒体节点。')
			]));
			streamingPane.appendChild(streamingCards);

			if (aiFormSection)
				aiPane.appendChild(aiFormSection);
			aiPane.insertBefore(callout('AI 页优先告诉你 ChatGPT、Claude、Gemini 等服务现在是否适合当前线路。', 'info'), aiPane.firstChild || null);
			aiPane.appendChild(E('div', { 'class': 'oca-summary-card oca-simple-only', 'style': 'margin-bottom:16px;' }, [
				E('div', { 'class': 'oca-summary-eyebrow' }, '看什么'),
				E('div', { 'class': 'oca-summary-title' }, '这里主要看 AI 服务是否稳定可用'),
				E('p', { 'class': 'oca-summary-copy' }, '如果这里只是偶尔能连，不代表长期可用。更重要的是它适不适合持续对话、写代码和调用接口。')
			]));
			aiPane.appendChild(aiCards);

			dnsPane.appendChild(callout('网站打不开、时好时坏时，先来这里刷新解析，再看是否恢复。', 'warn'));
			dnsPane.appendChild(dnsCards);

			if (autoFormSection)
				autoPane.appendChild(autoFormSection);
			autoPane.insertBefore(callout('自动切换不是越激进越好。这里优先给你更稳妥、可解释的建议。', 'info'), autoPane.firstChild || null);
			autoPane.appendChild(switchCards);

			splitPane.appendChild(callout('网站走向检测会告诉你：这个网站最后到底走了哪条路、从哪个出口出去。', 'warn'));
			splitPane.appendChild(E('div', { 'class': 'oca-summary-card oca-simple-only', 'style': 'margin-bottom:16px;' }, [
				E('div', { 'class': 'oca-summary-eyebrow' }, '看什么'),
				E('div', { 'class': 'oca-summary-title' }, '这里主要看网站最后走了哪条路'),
				E('p', { 'class': 'oca-summary-copy' }, '如果网站本该走代理却走了直连，或者本该国内直连却绕远路，这一页最容易看出来。')
			]));
			splitPane.appendChild(customRouteCards);
			splitPane.appendChild(splitTunnelCards);

			var tabDefs = [
				{ key: 'subconvert', label: '① 转换订阅与导入 OpenClash', pane: subConvertPane },
				{ key: 'overview', label: '② 基础场景 / 状态 / 建议', pane: overviewPane },
				{ key: 'checkup', label: '③ 一键体检', pane: checkupPane },
				{ key: 'streaming', label: '流媒体检测', pane: streamingPane },
				{ key: 'ai', label: 'AI 服务测试', pane: aiPane },
				{ key: 'dns', label: 'DNS 检测与修复', pane: dnsPane },
				{ key: 'auto', label: '自动切换建议', pane: autoPane },
				{ key: 'split', label: '网站走向检测', pane: splitPane }
			];

			var activeTab = getSavedTab();
			if (![ 'subconvert', 'overview', 'checkup', 'streaming', 'ai', 'dns', 'auto', 'split' ].some(function(key) { return key === activeTab; }))
				activeTab = 'subconvert';

			var tabBar = E('div', { 'class': 'oca-tabbar' });
			var tabContent = E('div');

			triggerMediaChecks = function(force) {
				currentMediaAi = window.__openclashAssistantMediaAiState || currentMediaAi;
				if (!mediaAi.can_run_live_test)
					return;
				if (!force && currentMediaAi && currentMediaAi.test_running) {
					startMediaAiPolling(true, currentMediaAi);
					return;
				}
				fs.exec('/usr/libexec/openclash-assistant/diag.sh', [ 'run-media-ai-live-test' ]).then(function() {
					currentMediaAi = { test_running: true };
					window.__openclashAssistantMediaAiState = currentMediaAi;
					startMediaAiPolling(true, { test_running: true });
				}).catch(function() {});
			};

			triggerSplitChecks = function(force) {
				var currentSplit = window.__openclashAssistantSplitTunnelState || splitTunnel;
				if (!force && currentSplit && currentSplit.test_running) {
					startSplitTunnelPolling(currentSplit);
					return;
				}
				fs.exec('/usr/libexec/openclash-assistant/diag.sh', [ 'run-split-tunnel-test' ]).then(function() {
					startSplitTunnelPolling({ test_running: true });
				}).catch(function() {});
			};

			var activateTab = function(tabKey) {
				saveTab(tabKey);
				setActiveTab(tabBar, tabContent, tabKey);

				if (tabKey === 'split')
					triggerSplitChecks(false);
				else if (shouldAutoStartChecks(currentMediaAi, tabKey))
					triggerMediaChecks(false);
			};

			openTab = function(tabKey) {
				activateTab(tabKey);
				tabBar.scrollIntoView(true);
			};
			actionOpenTab = openTab;

			runAssistantCheckup = function() {
				openTab('checkup');
				triggerMediaChecks(true);
				triggerSplitChecks(true);
			};

			tabDefs.forEach(function(tab) {
				tabBar.appendChild(E('button', {
					'class': 'btn cbi-button oca-tab' + (tab.key === activeTab ? ' active' : ''),
					'data-tab-key': tab.key,
					'click': function(ev) {
						ev.preventDefault();
						activateTab(tab.key);
					}
				}, [ tab.label ]));

				if (tab.key !== activeTab)
					tab.pane.style.display = 'none';
				tabContent.appendChild(tab.pane);
			});

			var introNode = node.querySelector('.cbi-map-descr');
			node.insertBefore(hero, introNode ? introNode.nextSibling : (node.firstChild ? node.firstChild.nextSibling : null));
			node.insertBefore(quickActions, hero.nextSibling);
			node.insertBefore(tabBar, quickActions.nextSibling);
			node.appendChild(tabContent);
			setActiveTab(tabBar, tabContent, activeTab);

			window.setTimeout(function() {
				Promise.all([
					fs.exec('/usr/libexec/openclash-assistant/diag.sh', [ 'status-json' ]).catch(function() { return { stdout: '{}' }; }),
					fs.exec('/usr/libexec/openclash-assistant/diag.sh', [ 'subconvert-lite-json' ]).catch(function() { return { stdout: '{}' }; })
				]).then(function(results) {
					var liveStatus = safeParse(results[0].stdout || '{}', {});
					var liveSubconvert = safeParse(results[1].stdout || '{}', {});

					if (Object.keys(liveStatus).length) {
						status = liveStatus;
						writeCachedJson('openclash-assistant-cache-status', liveStatus);
					}
					if (Object.keys(liveSubconvert).length) {
						subconvert = liveSubconvert;
						writeCachedJson('openclash-assistant-cache-subconvert-lite', liveSubconvert);
					}

					updateLiveSummaryCards(status || {}, subconvert || {});
				}).catch(function() {});
			}, 60);

			if (shouldAutoStartChecks(mediaAi, activeTab))
				triggerMediaChecks(false);
			else if (activeTab === 'split')
				triggerSplitChecks(false);
			else
				startMediaAiPolling(mediaAi.can_run_live_test, mediaAi);

			return node;
		});
	}
});
