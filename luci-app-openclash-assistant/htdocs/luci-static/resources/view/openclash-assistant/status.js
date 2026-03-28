'use strict';
'require view';

return view.extend({
	render: function() {
		var target = (typeof L !== 'undefined' && L.url)
			? L.url('admin/services/openclash-assistant')
			: '/cgi-bin/luci/admin/services/openclash-assistant';

		window.setTimeout(function() {
			window.location.href = target;
		}, 30);

		return E('div', { 'class': 'cbi-section' }, [
			E('h3', '页面已迁移'),
			E('p', '旧的 status 视图已合并到 overview 工作台。'),
			E('p', [
				E('a', { 'href': target }, '打开新版 OpenClash 助手')
			])
		]);
	}
});
