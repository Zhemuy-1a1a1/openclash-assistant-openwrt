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

function yesNo(value) {
	return value ? '是' : '否';
}

function preBlock(text) {
	return E('pre', {
		'style': 'white-space:pre-wrap;word-break:break-all;background:#f6f8fa;padding:12px;border-radius:8px;'
	}, text || '-');
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
	var color = '#6b7280';
	if (tone === 'good')
		color = '#16a34a';
	else if (tone === 'warn')
		color = '#d97706';
	else if (tone === 'bad')
		color = '#dc2626';

	return E('span', {
		'style': 'display:inline-block;margin-right:8px;margin-bottom:6px;padding:2px 8px;border-radius:999px;background:' + color + ';color:#fff;font-size:12px;'
	}, label);
}

function actionButton(label, onClick) {
	return E('button', {
		'class': 'btn cbi-button cbi-button-apply',
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

function updateAccessCardNodes(mediaAi) {
	Array.prototype.forEach.call(document.querySelectorAll('[data-media-card]'), function(card) {
		var key = card.getAttribute('data-media-card');
		var statusNode = card.querySelector('[data-field="status"]');
		var latencyNode = card.querySelector('[data-field="latency"]');
		var httpNode = card.querySelector('[data-field="http"]');
		var detailNode = card.querySelector('[data-field="detail"]');
		var tone = mediaAi[key + '_tone'] || 'warn';
		var detail = mediaAi[key + '_detail'] || '';
		var footer = 'HTTP ' + (mediaAi[key + '_http_code'] || '-');
		var showFooter = tone !== 'good';

		if (detail && detail !== '-' && detail.indexOf('连接正常') === -1)
			footer += ' · ' + detail;

		if (statusNode) {
			statusNode.textContent = mediaAi[key + '_status_text'] || '暂无结果';
			statusNode.style.color = toneColor(tone);
		}
		card.setAttribute('data-media-status', mediaAi[key + '_status'] || '');
		if (latencyNode)
			latencyNode.textContent = mediaAi[key + '_latency_ms'] ? (mediaAi[key + '_latency_ms'] + ' ms') : '-';
		if (httpNode) {
			httpNode.textContent = footer;
			httpNode.style.display = showFooter ? '' : 'none';
		}
		if (detailNode)
			detailNode.textContent = detail;
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

	var poll = function() {
		fs.exec('/usr/libexec/openclash-assistant/diag.sh', [ 'split-tunnel-json' ]).then(function(res) {
			var nextState = safeParse(res.stdout || '{}', {});
			window.__openclashAssistantSplitTunnelState = nextState;
			updateSplitTunnelCardNodes(nextState);

			if (nextState.test_running)
				window.setTimeout(poll, 4000);
		}).catch(function() {});
	};

	window.setTimeout(poll, 4000);
}

function getSavedTab() {
	try {
		return window.localStorage.getItem('openclash-assistant-tab') || 'overview';
	} catch (error) {
		return 'overview';
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

function countryFlag(code) {
	if (!code || code.length !== 2)
		return '';

	return code.toUpperCase().replace(/./g, function(char) {
		return String.fromCodePoint(127397 + char.charCodeAt(0));
	});
}

function shouldAutoStartChecks(mediaAi, activeTab) {
	if (activeTab !== 'access' && activeTab !== 'ai')
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
	{ key: 'gemini', label: 'Gemini' }
];

var streamingTargets = mediaTargets.filter(function(item) {
	return [ 'openai', 'claude', 'gemini' ].indexOf(item.key) === -1;
});

var aiTargets = mediaTargets.filter(function(item) {
	return [ 'openai', 'claude', 'gemini' ].indexOf(item.key) >= 0;
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

return view.extend({
	load: function() {
		return Promise.all([
			fs.exec('/usr/libexec/openclash-assistant/diag.sh', [ 'status-json' ]).catch(function() { return { stdout: '{}' }; }),
			fs.exec('/usr/libexec/openclash-assistant/diag.sh', [ 'advice-json' ]).catch(function() { return { stdout: '{}' }; }),
			fs.exec('/usr/libexec/openclash-assistant/diag.sh', [ 'media-ai-json' ]).catch(function() { return { stdout: '{}' }; }),
			fs.exec('/usr/libexec/openclash-assistant/diag.sh', [ 'split-tunnel-json' ]).catch(function() { return { stdout: '{}' }; }),
			fs.exec('/usr/libexec/openclash-assistant/diag.sh', [ 'flush-dns-json' ]).catch(function() { return { stdout: '{}' }; }),
			fs.exec('/usr/libexec/openclash-assistant/diag.sh', [ 'templates-json' ]).catch(function() { return { stdout: '{"templates":[]}' }; }),
			fs.exec('/usr/libexec/openclash-assistant/diag.sh', [ 'auto-switch-json' ]).catch(function() { return { stdout: '{}' }; }),
			fs.exec('/usr/libexec/openclash-assistant/diag.sh', [ 'subconvert-json' ]).catch(function() { return { stdout: '{}' }; })
		]);
	},

	render: function(data) {
		var status = safeParse(data[0].stdout || '{}', {});
		var advice = safeParse(data[1].stdout || '{}', {});
		var mediaAi = safeParse(data[2].stdout || '{}', {});
		var currentMediaAi = mediaAi;
		window.__openclashAssistantMediaAiState = mediaAi;
		var splitTunnel = safeParse(data[3].stdout || '{}', {});
		window.__openclashAssistantSplitTunnelState = splitTunnel;
		var flushDns = safeParse(data[4].stdout || '{}', {});
		var templatesData = safeParse(data[5].stdout || '{"templates":[]}', { templates: [] });
		var autoSwitch = safeParse(data[6].stdout || '{}', {});
		var subconvert = safeParse(data[7].stdout || '{}', {});
		var templates = templatesData.templates || [];

		var map = new form.Map('openclash-assistant', 'OpenClash 助手',
			'面向旁路由、DNS、Fake-IP、TUN、访问检查、节点自动切换与订阅转换的中文辅助页面。');

		var option;
		var baseSection = map.section(form.TypedSection, 'assistant', '一、基础场景');
		baseSection.anonymous = true;
		baseSection.addremove = false;

		option = baseSection.option(form.ListValue, 'routing_role', '部署角色');
		option.value('bypass_router', '旁路由');
		option.value('main_router', '主路由');
		option.value('single_arm', '单臂 / 混合模式');
		option.default = 'bypass_router';

		option = baseSection.option(form.ListValue, 'preferred_mode', '偏好模式');
		option.value('auto', '自动');
		option.value('fake-ip', 'Fake-IP（假 IP）');
		option.value('tun', 'TUN 模式');
		option.value('compatibility', '兼容优先');
		option.default = 'auto';

		option = baseSection.option(form.Flag, 'needs_ipv6', '需要 IPv6');
		option.default = '0';
		option = baseSection.option(form.Flag, 'has_public_services', '局域网服务需要公网访问');
		option.default = '0';
		option = baseSection.option(form.Flag, 'uses_tailscale', '使用 Tailscale / 其他组网工具');
		option.default = '0';
		option = baseSection.option(form.Flag, 'gaming_devices', '需要游戏设备兼容性');
		option.default = '0';
		option = baseSection.option(form.Flag, 'low_maintenance', '希望省心稳定');
		option.default = '1';

		var streamingSection = map.section(form.TypedSection, 'assistant', '二、流媒体检测');
		streamingSection.anonymous = true;
		streamingSection.addremove = false;

		option = streamingSection.option(form.DummyValue, '_streaming_auto_note', '检测方式');
		option.rawhtml = true;
		option.cfgvalue = function() {
			return '默认对全部流媒体目标自动执行访问检查。';
		};

		var aiSection = map.section(form.TypedSection, 'assistant', '三、AI 检测');
		aiSection.anonymous = true;
		aiSection.addremove = false;

		option = aiSection.option(form.DummyValue, '_ai_hint', '检测方式');
		option.rawhtml = true;
		option.cfgvalue = function() {
			return '默认对 OpenAI、Claude、Gemini 自动执行访问检查。';
		};

		var autoSection = map.section(form.TypedSection, 'assistant', '四、节点自动切换');
		autoSection.anonymous = true;
		autoSection.addremove = false;
		option = autoSection.option(form.Flag, 'auto_switch_enabled', '启用自动切换建议');
		option.default = '1';
		option = autoSection.option(form.ListValue, 'auto_switch_logic', '自动切换逻辑');
		option.value('urltest', '延迟优先（Urltest）');
		option.value('random', '随机轮换');
		option.default = 'urltest';
		option = autoSection.option(form.Value, 'auto_switch_interval', '切换检测间隔（分钟）');
		option.datatype = 'uinteger';
		option.default = '30';
		option = autoSection.option(form.Flag, 'auto_switch_expand_group', '自动展开分组');
		option.default = '1';
		option = autoSection.option(form.Flag, 'auto_switch_close_con', '切换后关闭旧连接');
		option.default = '1';

		var subSection = map.section(form.TypedSection, 'assistant', '五、订阅转换');
		subSection.anonymous = true;
		subSection.addremove = false;
		option = subSection.option(form.Flag, 'sub_convert_enabled', '启用订阅转换建议');
		option.default = '1';
		option = subSection.option(form.Value, 'sub_convert_source', '原始订阅地址');
		option.placeholder = 'https://example.com/sub?...';
		option = subSection.option(form.ListValue, 'sub_convert_backend', '转换后端');
		option.value('https://api.dler.io/sub', 'api.dler.io');
		option.value('https://api.wcc.best/sub', 'api.wcc.best');
		option.value('https://api.asailor.org/sub', 'api.asailor.org');
		option.default = 'https://api.dler.io/sub';
		option = subSection.option(form.ListValue, 'sub_convert_template', '转换模板');
		templates.forEach(function(item) {
			option.value(item.id, item.name);
		});
		option.value('custom', '自定义模板');
		option.default = 'ACL4SSR_Online_Mini_MultiMode.ini';
		option = subSection.option(form.Value, 'sub_convert_custom_template_url', '自定义模板地址');
		option.placeholder = 'https://raw.githubusercontent.com/...';
		option.depends('sub_convert_template', 'custom');
		option = subSection.option(form.ListValue, 'sub_convert_emoji', '节点名称添加 Emoji');
		option.value('false', '关闭');
		option.value('true', '开启');
		option.default = 'true';
		option = subSection.option(form.ListValue, 'sub_convert_udp', '保留 UDP');
		option.value('false', '关闭');
		option.value('true', '开启');
		option.default = 'true';
		option = subSection.option(form.ListValue, 'sub_convert_sort', '按规则排序');
		option.value('false', '关闭');
		option.value('true', '开启');
		option.default = 'false';
		option = subSection.option(form.ListValue, 'sub_convert_skip_cert_verify', '跳过证书校验');
		option.value('false', '关闭');
		option.value('true', '开启');
		option.default = 'false';
		option = subSection.option(form.ListValue, 'sub_convert_append_node_type', '节点名追加类型');
		option.value('false', '关闭');
		option.value('true', '开启');
		option.default = 'true';

		var runAction = function(action) {
			return fs.exec('/usr/libexec/openclash-assistant/diag.sh', [ action ]).then(function(res) {
				var result = safeParse(res.stdout || '{}', {});
				window.alert(result.message || '执行完成');
				return result;
			}).catch(function(err) {
				window.alert('执行失败：' + err);
				throw err;
			});
		};

		return map.render().then(function(node) {
			var streamingSuccessCount = countByStatus(streamingTargets, mediaAi, function(status) {
				return status === 'reachable' || status === 'available' || status === 'full_support';
			});
			var streamingIssueCount = countByStatus(streamingTargets, mediaAi, isIssueStatus);
			var aiSuccessCount = countByStatus(aiTargets, mediaAi, function(status) {
				return status === 'reachable' || status === 'available' || status === 'full_support';
			});
			var aiIssueCount = countByStatus(aiTargets, mediaAi, isIssueStatus);

			var statusCards = E('div', { 'class': 'cbi-section' }, [
				E('h3', '运行状态概览'),
				E('p', [
					badge(status.running ? '运行中' : '未运行', status.running ? 'good' : 'bad'),
					badge(status.installed ? '已安装' : '未安装', status.installed ? 'good' : 'bad'),
					badge(status.dnsmasq_full ? 'dnsmasq-full 正常' : '缺少 dnsmasq-full', status.dnsmasq_full ? 'good' : 'warn'),
					badge(status.stream_auto_select === '1' ? 'OpenClash 已开启自动切换' : 'OpenClash 未开启自动切换', status.stream_auto_select === '1' ? 'good' : 'warn'),
					badge('DNS 诊断：' + (status.dns_diag_level === 'good' ? '正常' : (status.dns_diag_level === 'bad' ? '异常' : '提示')), status.dns_diag_level || 'warn')
				]),
				E('table', { 'class': 'table cbi-section-table' }, [
					E('tr', [ E('td', '服务已启用'), E('td', yesNo(status.enabled)) ]),
					E('tr', [ E('td', '已检测到 OpenClash 配置'), E('td', yesNo(status.openclash_config)) ]),
					E('tr', [ E('td', '检测到配置文件数量'), E('td', String(status.config_count || 0)) ]),
					E('tr', [ E('td', '支持 TUN 模式'), E('td', yesNo(status.tun)) ]),
					E('tr', [ E('td', '已安装 nftables'), E('td', yesNo(status.nft)) ]),
					E('tr', [ E('td', '支持 Firewall4'), E('td', yesNo(status.firewall4)) ]),
					E('tr', [ E('td', '支持 ipset'), E('td', yesNo(status.ipset)) ]),
					E('tr', [ E('td', 'DNS 服务链路'), E('td', status.dns_chain || '-') ]),
					E('tr', [ E('td', 'DNS 诊断摘要'), E('td', status.dns_diag_summary || '-') ]),
					E('tr', [ E('td', 'DNS 建议动作'), E('td', status.dns_diag_action || '-') ])
				])
			]);

			var adviceCards = E('div', { 'class': 'cbi-section' }, [
				E('h3', '基础建议'),
				E('p', [
					badge('方案：' + (advice.profile || '未知'), riskTone(advice.risk)),
					badge('风险：' + zhRisk(advice.risk), riskTone(advice.risk))
				]),
				E('table', { 'class': 'table cbi-section-table' }, [
					E('tr', [ E('td', '原因'), E('td', advice.why || '-') ]),
					E('tr', [ E('td', '常见风险'), E('td', advice.pitfalls || '-') ]),
					E('tr', [ E('td', '下一步检查清单'), E('td', advice.checklist || '-') ])
				])
			]);

			var makeMediaResultCards = function(items) {
				return E('div', {
					'style': 'display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:12px;margin-top:12px;'
				}, items.map(function(item) {
					var tone = mediaAi[item.key + '_tone'] || 'warn';
					var color = '#d97706';
					var detail = mediaAi[item.key + '_detail'] || '';
					var footer = 'HTTP ' + (mediaAi[item.key + '_http_code'] || '-');
					var showFooter = tone !== 'good';

					if (tone === 'good')
						color = '#16a34a';
					else if (tone === 'bad')
						color = '#dc2626';

					if (detail && detail !== '-' && detail.indexOf('连接正常') === -1)
						footer += ' · ' + detail;

					return E('div', {
						'style': 'border:1px solid #e5e7eb;border-radius:16px;padding:14px 16px;background:linear-gradient(180deg,#ffffff 0%,#f8fafc 100%);box-shadow:0 1px 2px rgba(15,23,42,0.04);min-height:' + (showFooter ? '132px' : '112px') + ';',
						'data-media-card': item.key,
						'data-media-status': mediaAi[item.key + '_status'] || ''
					}, [
						E('div', { 'style': 'font-size:15px;font-weight:600;color:#111827;margin-bottom:8px;' }, item.label),
						E('div', { 'data-field': 'status', 'style': 'font-size:13px;color:' + color + ';font-weight:700;letter-spacing:0.02em;margin-bottom:8px;' }, mediaAi[item.key + '_status_text'] || '暂无结果'),
						E('div', { 'data-field': 'latency', 'style': 'font-size:32px;line-height:1.05;font-weight:800;color:#111827;' }, mediaAi[item.key + '_latency_ms'] ? (mediaAi[item.key + '_latency_ms'] + ' ms') : '-'),
						E('div', { 'data-field': 'http', 'style': 'font-size:11px;color:#6b7280;margin-top:10px;line-height:1.4;' + (showFooter ? '' : 'display:none;') }, footer),
						E('div', { 'data-field': 'detail', 'style': 'display:none;' }, detail)
					]);
				}));
			};

			var activeFilter = getSavedFilter();
			if ([ 'all', 'issues', 'streaming', 'ai' ].indexOf(activeFilter) < 0)
				activeFilter = 'all';

			var filterBar = E('div', { 'style': 'margin:12px 0;' }, [
				actionButton('显示全部', function() {
					saveFilter('all');
					applyMediaFilter('all');
				}),
				actionButton('只看异常', function() {
					saveFilter('issues');
					applyMediaFilter('issues');
				}),
				actionButton('只看流媒体', function() {
					saveFilter('streaming');
					applyMediaFilter('streaming');
				}),
				actionButton('只看 AI', function() {
					saveFilter('ai');
					applyMediaFilter('ai');
				})
			]);

			var visibleStreamingTargets = activeFilter === 'issues'
				? streamingTargets.filter(function(item) { return isIssueStatus(mediaAi[item.key + '_status'] || ''); })
				: streamingTargets;
			var visibleAiTargets = activeFilter === 'issues'
				? aiTargets.filter(function(item) { return isIssueStatus(mediaAi[item.key + '_status'] || ''); })
				: aiTargets;

			var streamingTableWrap = E('div', { 'data-media-group': 'streaming' }, [
				E('h4', '流媒体'),
				E('p', [
					badge('可用：' + String(streamingSuccessCount), streamingSuccessCount > 0 ? 'good' : 'warn'),
					badge('异常：' + String(streamingIssueCount), streamingIssueCount > 0 ? 'bad' : 'good')
				]),
				makeMediaResultCards(visibleStreamingTargets),
				visibleStreamingTargets.length === 0 ? E('p', { 'style': 'color:#6b7280;' }, '当前筛选条件下没有流媒体异常项。') : E('div')
			]);

			var aiTableWrap = E('div', { 'data-media-group': 'ai', 'style': 'margin-top:16px;' }, [
				E('h4', 'AI'),
				E('p', [
					badge('可访问：' + String(aiSuccessCount), aiSuccessCount > 0 ? 'good' : 'warn'),
					badge('异常：' + String(aiIssueCount), aiIssueCount > 0 ? 'bad' : 'good')
				]),
				makeMediaResultCards(visibleAiTargets),
				visibleAiTargets.length === 0 ? E('p', { 'style': 'color:#6b7280;' }, '当前筛选条件下没有 AI 异常项。') : E('div')
			]);

			var accessCards = E('div', { 'class': 'cbi-section' }, [
				E('h3', '访问检查'),
				E('p', [
					badge(mediaAi.test_running ? '后台检测中' : '检测空闲', mediaAi.test_running ? 'warn' : 'good'),
					badge('进度 ' + String(mediaAi.completed_count || 0) + '/' + String(mediaAi.selected_count || 0), mediaAi.test_running ? 'warn' : 'good'),
					badge('连接正常 ' + String(mediaAi.success_count || 0), (mediaAi.success_count || 0) > 0 ? 'good' : 'warn'),
					badge('待处理 ' + String((mediaAi.partial_count || 0) + (mediaAi.issue_count || 0)), (mediaAi.issue_count || 0) > 0 ? 'bad' : 'warn')
				]),
				E('table', { 'class': 'table cbi-section-table' }, [
					E('tr', [ E('td', '检测说明'), E('td', { 'data-summary-field': 'summary' }, mediaAi.summary || '-') ]),
					E('tr', [ E('td', '最近一次检查'), E('td', { 'data-summary-field': 'last_run_at' }, mediaAi.last_run_at || '暂无') ]),
					E('tr', [ E('td', '检查范围'), E('td', '默认检查全部流媒体站点') ])
				]),
				filterBar
			]);

			if (activeFilter !== 'ai')
				accessCards.appendChild(streamingTableWrap);
			if (activeFilter !== 'streaming')
				accessCards.appendChild(aiTableWrap);
			accessCards.appendChild(E('p', { 'style': 'color:#6b7280;' }, mediaAi.can_run_live_test ? '页面会自动执行访问检查并局部刷新结果。' : '当前设备缺少检测依赖，只能显示静态状态。'));
			if (mediaAi.test_running)
				accessCards.appendChild(E('p', { 'style': 'color:#d97706;' }, '检测进行中，当前标签页内容会局部刷新。'));
			accessCards.appendChild(E('p', { 'style': 'color:#6b7280;' }, '进入标签页后会自动触发，无需手动开始。'));

			var switchCards = E('div', { 'class': 'cbi-section' }, [
				E('h3', '节点自动切换建议'),
				E('p', [
					badge(autoSwitch.enabled ? '助手建议：开启' : '助手建议：关闭', autoSwitch.enabled ? 'good' : 'warn'),
					badge('逻辑：' + (autoSwitch.logic_label || '未知'), 'warn'),
					badge('当前 OpenClash：' + (status.stream_auto_select === '1' ? '已开启' : '未开启'), status.stream_auto_select === '1' ? 'good' : 'warn')
				]),
				E('table', { 'class': 'table cbi-section-table' }, [
					E('tr', [ E('td', '检测间隔'), E('td', String(autoSwitch.interval || '-')) ]),
					E('tr', [ E('td', '当前 OpenClash 逻辑'), E('td', status.stream_auto_select_logic || '-') ]),
					E('tr', [ E('td', '当前 OpenClash 间隔'), E('td', status.stream_auto_select_interval || '-') ]),
					E('tr', [ E('td', '建议说明'), E('td', autoSwitch.suggestion || '-') ])
				]),
				E('p', { 'style': 'color:#6b7280;' }, '如果你刚改了上面的选项，请先点页面顶部“保存并应用”，再执行一键应用。'),
				actionButton('一键应用自动切换到 OpenClash', function() {
					runAction('apply-auto-switch');
				}),
				preBlock(autoSwitch.commands)
			]);

			var subCards = E('div', { 'class': 'cbi-section' }, [
				E('h3', '订阅转换建议'),
				E('p', [
					badge('当前模板：' + (subconvert.template_name || '未设置'), 'warn'),
					badge('推荐模板：' + (subconvert.recommended_template_name || '未匹配'), 'good'),
					badge(subconvert.enabled ? '助手建议：开启订阅转换' : '助手建议：关闭订阅转换', subconvert.enabled ? 'good' : 'warn')
				]),
				E('table', { 'class': 'table cbi-section-table' }, [
					E('tr', [ E('td', '模板地址'), E('td', subconvert.template_url || '-') ]),
					E('tr', [ E('td', '推荐模板地址'), E('td', subconvert.recommended_template_url || '-') ]),
					E('tr', [ E('td', '转换后端'), E('td', subconvert.backend || '-') ]),
					E('tr', [ E('td', '说明'), E('td', subconvert.hint || '-') ])
				]),
				actionButton('导入现有 OpenClash 订阅参数', function() {
					runAction('sync-subconvert-from-openclash');
				}),
				E('p', { 'style': 'color:#6b7280;' }, '如果你刚改了上面的订阅参数，请先点页面顶部“保存并应用”，再执行一键写入。'),
				actionButton('一键写入订阅到 OpenClash', function() {
					runAction('apply-subconvert');
				}),
				E('p', { 'style': 'color:#6b7280;' }, '下面会生成一条可直接用于 OpenClash / subconverter 的转换地址。模板参考了 GitHub 上常用的 ACL4SSR 与 Aethersailor 模板。'),
				preBlock(subconvert.convert_url || '请先填写原始订阅地址，再保存并刷新页面。'),
				E('p', { 'style': 'color:#6b7280;' }, '如果你想直接把它写进 OpenClash，可以复制下面这段 UCI 命令。'),
				preBlock(subconvert.commands)
			]);

			var dnsCards = E('div', { 'class': 'cbi-section' }, [
				E('h3', 'Flush DNS'),
				E('p', [
					badge(flushDns.dnsmasq_running ? 'dnsmasq 运行中' : 'dnsmasq 未运行', flushDns.dnsmasq_running ? 'good' : 'warn'),
					flushDns.smartdns_available ? badge(flushDns.smartdns_running ? 'smartdns 运行中' : 'smartdns 未运行', flushDns.smartdns_running ? 'good' : 'warn') : badge('smartdns 未启用', 'warn'),
					badge(flushDns.openclash_running ? 'OpenClash 运行中' : 'OpenClash 未运行', flushDns.openclash_running ? 'good' : 'warn'),
					badge('DNS 诊断：' + (flushDns.dns_diag_level === 'good' ? '正常' : (flushDns.dns_diag_level === 'bad' ? '异常' : '提示')), flushDns.dns_diag_level || 'warn')
				]),
				E('div', {
					'style': 'display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:12px;margin-top:12px;'
				}, [
					E('div', {
						'style': 'border:1px solid #e5e7eb;border-radius:16px;padding:14px 16px;background:linear-gradient(180deg,#ffffff 0%,#f8fafc 100%);box-shadow:0 1px 2px rgba(15,23,42,0.04);'
					}, [
						E('div', { 'style': 'font-size:15px;font-weight:600;color:#111827;margin-bottom:8px;' }, '刷新时间'),
						E('div', { 'data-dns-field': 'last_run_at', 'style': 'font-size:28px;line-height:1.1;font-weight:800;color:#111827;' }, flushDns.last_run_at || '暂无'),
						E('div', { 'style': 'font-size:11px;color:#6b7280;margin-top:10px;line-height:1.4;' }, '最近一次执行时间')
					]),
					E('div', {
						'style': 'border:1px solid #e5e7eb;border-radius:16px;padding:14px 16px;background:linear-gradient(180deg,#ffffff 0%,#f8fafc 100%);box-shadow:0 1px 2px rgba(15,23,42,0.04);'
					}, [
						E('div', { 'style': 'font-size:15px;font-weight:600;color:#111827;margin-bottom:8px;' }, '刷新结果'),
						E('div', { 'data-dns-field': 'last_message', 'style': 'font-size:13px;color:#0f172a;font-weight:600;line-height:1.6;' }, flushDns.last_message || '暂无'),
						E('div', { 'style': 'font-size:11px;color:#6b7280;margin-top:10px;line-height:1.4;' }, flushDns.hint || '-')
					]),
					E('div', {
						'style': 'border:1px solid #e5e7eb;border-radius:16px;padding:14px 16px;background:linear-gradient(180deg,#ffffff 0%,#f8fafc 100%);box-shadow:0 1px 2px rgba(15,23,42,0.04);'
					}, [
						E('div', { 'style': 'font-size:15px;font-weight:600;color:#111827;margin-bottom:8px;' }, 'DNS 链路'),
						E('div', { 'data-dns-field': 'dns_chain', 'style': 'font-size:13px;color:#0f172a;font-weight:700;line-height:1.6;' }, flushDns.dns_chain || '-'),
						E('div', { 'data-dns-field': 'dns_diag_summary', 'style': 'font-size:12px;color:#334155;margin-top:8px;line-height:1.6;' }, flushDns.dns_diag_summary || '-')
					]),
					E('div', {
						'style': 'border:1px solid #e5e7eb;border-radius:16px;padding:14px 16px;background:linear-gradient(180deg,#ffffff 0%,#f8fafc 100%);box-shadow:0 1px 2px rgba(15,23,42,0.04);'
					}, [
						E('div', { 'style': 'font-size:15px;font-weight:600;color:#111827;margin-bottom:8px;' }, '建议动作'),
						E('div', { 'data-dns-field': 'dns_diag_action', 'style': 'font-size:12px;color:#334155;line-height:1.7;' }, flushDns.dns_diag_action || '-')
					])
				]),
				actionButton('立即 Flush DNS', function() {
					runAction('flush-dns').then(function() {
						return fs.exec('/usr/libexec/openclash-assistant/diag.sh', [ 'flush-dns-json' ]);
					}).then(function(res) {
						var nextFlushDns = safeParse(res.stdout || '{}', {});
						Array.prototype.forEach.call(dnsCards.querySelectorAll('[data-dns-field]'), function(node) {
							var field = node.getAttribute('data-dns-field');
							if (field === 'last_run_at')
								node.textContent = nextFlushDns.last_run_at || '暂无';
							else if (field === 'last_message')
								node.textContent = nextFlushDns.last_message || '暂无';
							else if (field === 'dns_chain')
								node.textContent = nextFlushDns.dns_chain || '-';
							else if (field === 'dns_diag_summary')
								node.textContent = nextFlushDns.dns_diag_summary || '-';
							else if (field === 'dns_diag_action')
								node.textContent = nextFlushDns.dns_diag_action || '-';
						});
					}).catch(function() {});
				}),
				E('p', { 'style': 'color:#6b7280;' }, '点击后会刷新本机 DNS 缓存，并尽量不影响当前页面其他区域。')
			]);

			var makeSplitTunnelCards = function(items) {
				return E('div', {
					'style': 'display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:12px;margin-top:12px;'
				}, items.map(function(item) {
					var tone = splitTunnel[item.key + '_tone'] || 'warn';
					var color = toneColor(tone);
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

					return E('div', {
						'style': 'border:1px solid #e5e7eb;border-radius:16px;padding:14px 16px;background:linear-gradient(180deg,#ffffff 0%,#f8fafc 100%);box-shadow:0 1px 2px rgba(15,23,42,0.04);min-height:' + (showFooter ? '132px' : '112px') + ';',
						'data-split-card': item.key
					}, [
						E('div', { 'style': 'font-size:15px;font-weight:600;color:#111827;margin-bottom:8px;' }, item.label),
						E('div', { 'style': 'font-size:11px;color:#6b7280;margin-bottom:6px;' }, item.group),
						E('div', { 'data-field': 'status', 'style': 'font-size:13px;color:' + color + ';font-weight:700;letter-spacing:0.02em;margin-bottom:8px;' }, splitTunnel[item.key + '_status_text'] || '暂无结果'),
						E('div', {
							'data-field': 'exit',
							'style': 'font-size:' + (isPrimary ? '13px' : '11px') + ';color:' + (exitParts.length ? '#0f172a' : '#94a3b8') + ';font-weight:' + (exitParts.length ? '700' : '500') + ';margin-bottom:8px;line-height:1.4;'
						}, exitParts.length ? exitParts.join(' / ') : '出口信息暂不可用'),
						E('div', { 'data-field': 'latency', 'style': 'font-size:32px;line-height:1.05;font-weight:800;color:#111827;' }, splitTunnel[item.key + '_latency_ms'] ? (splitTunnel[item.key + '_latency_ms'] + ' ms') : '-'),
						E('div', { 'data-field': 'http', 'style': 'font-size:11px;color:#6b7280;margin-top:10px;line-height:1.4;' + (showFooter ? '' : 'display:none;') }, footer)
					]);
				}));
			};

			var splitPrimaryTargets = splitTunnelTargets.filter(function(item) {
				return splitTunnelPrimaryTargets.indexOf(item.key) >= 0;
			});
			splitPrimaryTargets = sortSplitTunnelTargets(splitPrimaryTargets, splitTunnel);

			var splitSecondaryTargets = splitTunnelTargets.filter(function(item) {
				return splitTunnelPrimaryTargets.indexOf(item.key) < 0;
			});
			splitSecondaryTargets = sortSplitTunnelTargets(splitSecondaryTargets, splitTunnel);

			var splitTunnelCards = E('div', { 'class': 'cbi-section' }, [
				E('h3', '分流测试'),
				E('p', [
					badge(splitTunnel.test_running ? '并发检测中' : '空闲', splitTunnel.test_running ? 'warn' : 'good'),
					badge(splitTunnel.test_running ? '结果完成后统一显示' : ('共 ' + String(splitTunnel.selected_count || 0) + ' 项'), splitTunnel.test_running ? 'warn' : 'good'),
					badge('连接正常 ' + String(splitTunnel.success_count || 0), (splitTunnel.success_count || 0) > 0 ? 'good' : 'warn'),
					badge('异常 ' + String(splitTunnel.issue_count || 0), (splitTunnel.issue_count || 0) > 0 ? 'bad' : 'good')
				]),
				E('table', { 'class': 'table cbi-section-table' }, [
					E('tr', [ E('td', '说明'), E('td', { 'data-split-summary': 'summary' }, splitTunnel.summary || '-') ]),
					E('tr', [ E('td', '最近一次检查'), E('td', { 'data-split-summary': 'last_run_at' }, splitTunnel.last_run_at || '暂无') ])
				]),
				E('h4', '核心分流结果'),
				E('p', { 'style': 'color:#6b7280;' }, '优先展示更适合做出口信息回显判断的目标。'),
				makeSplitTunnelCards(splitPrimaryTargets),
				E('h4', { 'style': 'margin-top:16px;' }, '补充目标'),
				E('p', { 'style': 'color:#6b7280;' }, '这些目标主要用于补充访问状态与延迟，不一定都能稳定回显出口信息。'),
				makeSplitTunnelCards(splitSecondaryTargets)
			]);

			var aiHintCards = E('div', { 'class': 'cbi-section' }, [
				E('h3', 'AI 检查摘要'),
				E('p', [
					badge('可访问：' + String(aiSuccessCount), aiSuccessCount > 0 ? 'good' : 'warn'),
					badge('异常：' + String(aiIssueCount), aiIssueCount > 0 ? 'bad' : 'good'),
					badge(mediaAi.test_running ? '后台检测中' : '检测空闲', mediaAi.test_running ? 'warn' : 'good')
				]),
				E('table', { 'class': 'table cbi-section-table' }, [
					E('tr', [ E('td', '最近一次检查'), E('td', { 'data-summary-field': 'last_run_at' }, mediaAi.last_run_at || '暂无') ]),
					E('tr', [ E('td', 'ChatGPT / OpenAI'), E('td', (mediaAi.openai_status_text || '暂无结果') + (mediaAi.openai_latency_ms ? (' / ' + mediaAi.openai_latency_ms + ' ms') : '')) ]),
					E('tr', [ E('td', 'Claude'), E('td', (mediaAi.claude_status_text || '暂无结果') + (mediaAi.claude_latency_ms ? (' / ' + mediaAi.claude_latency_ms + ' ms') : '')) ]),
					E('tr', [ E('td', 'Gemini'), E('td', (mediaAi.gemini_status_text || '暂无结果') + (mediaAi.gemini_latency_ms ? (' / ' + mediaAi.gemini_latency_ms + ' ms') : '')) ])
				]),
				E('p', { 'style': 'color:#6b7280;' }, 'AI 详细结果请看“访问检查”。')
			]);

			var formSections = Array.prototype.slice.call(node.querySelectorAll('.cbi-section'));
			var baseFormSection = formSections[0] || null;
			var mediaFormSection = formSections[1] || null;
			var aiFormSection = formSections[2] || null;
			var autoFormSection = formSections[3] || null;
			var subFormSection = formSections[4] || null;

			var overviewPane = E('div', { 'data-tab-pane': 'overview' });
			var accessPane = E('div', { 'data-tab-pane': 'access' });
			var splitPane = E('div', { 'data-tab-pane': 'split' });
			var aiPane = E('div', { 'data-tab-pane': 'ai' });
			var dnsPane = E('div', { 'data-tab-pane': 'dns' });
			var autoPane = E('div', { 'data-tab-pane': 'auto' });
			var subPane = E('div', { 'data-tab-pane': 'sub' });

			if (baseFormSection)
				overviewPane.appendChild(baseFormSection);
			overviewPane.appendChild(statusCards);
			overviewPane.appendChild(adviceCards);

			if (mediaFormSection)
				accessPane.appendChild(mediaFormSection);
			accessPane.appendChild(accessCards);

			splitPane.appendChild(splitTunnelCards);

			if (aiFormSection)
				aiPane.appendChild(aiFormSection);
			aiPane.appendChild(aiTableWrap);
			aiPane.appendChild(aiHintCards);

			dnsPane.appendChild(dnsCards);

			if (autoFormSection)
				autoPane.appendChild(autoFormSection);
			autoPane.appendChild(switchCards);

			if (subFormSection)
				subPane.appendChild(subFormSection);
			subPane.appendChild(subCards);

			var tabDefs = [
				{ key: 'overview', label: '概览', pane: overviewPane },
				{ key: 'access', label: '访问检查', pane: accessPane },
				{ key: 'split', label: '分流测试', pane: splitPane },
				{ key: 'ai', label: 'AI 检测', pane: aiPane },
				{ key: 'dns', label: 'DNS 工具', pane: dnsPane },
				{ key: 'auto', label: '自动切换', pane: autoPane },
				{ key: 'sub', label: '订阅转换', pane: subPane }
			];

			var activeTab = getSavedTab();
			if (![ 'overview', 'access', 'split', 'ai', 'dns', 'auto', 'sub' ].some(function(key) { return key === activeTab; }))
				activeTab = 'overview';

			var tabBar = E('div', { 'style': 'display:flex;gap:8px;flex-wrap:wrap;margin:16px 0;' });
			var tabContent = E('div');

			tabDefs.forEach(function(tab) {
				tabBar.appendChild(E('button', {
					'class': 'btn cbi-button',
					'style': 'border-radius:999px;padding:6px 14px;' + (tab.key === activeTab ? 'background:#0f766e;color:#fff;border-color:#0f766e;' : ''),
					'click': function(ev) {
						ev.preventDefault();
						saveTab(tab.key);
						Array.prototype.forEach.call(tabContent.children, function(pane) {
							pane.style.display = 'none';
						});
						tab.pane.style.display = '';
						Array.prototype.forEach.call(tabBar.children, function(btn) {
							btn.style.background = '';
							btn.style.color = '';
							btn.style.borderColor = '';
						});
						this.style.background = '#0f766e';
						this.style.color = '#fff';
						this.style.borderColor = '#0f766e';

						currentMediaAi = window.__openclashAssistantMediaAiState || currentMediaAi;
						if (tab.key === 'split') {
							var currentSplit = window.__openclashAssistantSplitTunnelState || splitTunnel;
							if (!currentSplit.test_running) {
								fs.exec('/usr/libexec/openclash-assistant/diag.sh', [ 'run-split-tunnel-test' ]).then(function() {
									startSplitTunnelPolling({ test_running: true });
								}).catch(function() {});
							}
						} else if (shouldAutoStartChecks(currentMediaAi, tab.key) && currentMediaAi.can_run_live_test) {
							fs.exec('/usr/libexec/openclash-assistant/diag.sh', [ 'run-media-ai-live-test' ]).then(function() {
								startMediaAiPolling(true, { test_running: true });
							}).catch(function() {});
						}
					}
				}, [ tab.label ]));

				if (tab.key !== activeTab)
					tab.pane.style.display = 'none';
				tabContent.appendChild(tab.pane);
			});

			node.insertBefore(tabBar, node.firstChild ? node.firstChild.nextSibling : null);
			node.appendChild(tabContent);
			applyMediaFilter(activeFilter);

			if (shouldAutoStartChecks(mediaAi, activeTab) && mediaAi.can_run_live_test) {
				fs.exec('/usr/libexec/openclash-assistant/diag.sh', [ 'run-media-ai-live-test' ]).then(function() {
					currentMediaAi = { test_running: true };
					window.__openclashAssistantMediaAiState = currentMediaAi;
					startMediaAiPolling(true, { test_running: true });
				}).catch(function() {});
			} else if (activeTab === 'split') {
				if (!splitTunnel.test_running) {
					fs.exec('/usr/libexec/openclash-assistant/diag.sh', [ 'run-split-tunnel-test' ]).then(function() {
						startSplitTunnelPolling({ test_running: true });
					}).catch(function() {});
				} else {
					startSplitTunnelPolling(splitTunnel);
				}
			} else {
				startMediaAiPolling(mediaAi.can_run_live_test, mediaAi);
			}

			return node;
		});
	}
});
