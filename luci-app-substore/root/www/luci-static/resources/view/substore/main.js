'use strict';
'require view';
'require form';
'require uci';
'require rpc';
'require fs';

var SERVICE = 'substore';

var VERSION_FILES = {
	backend: '/usr/libexec/substore/backend.version',
	frontend: '/usr/libexec/substore/frontend.version'
};

var UPDATE_SCRIPTS = {
	backend: '/usr/libexec/substore/update-backend.sh',
	frontend: '/usr/libexec/substore/update-frontend.sh'
};

var callServiceList = rpc.declare({
	object: 'service',
	method: 'list',
	params: ['name'],
	expect: { '': {} }
});

var callInitAction = rpc.declare({
	object: 'rc',
	method: 'init',
	params: ['name', 'action']
});

var callFileExec = rpc.declare({
	object: 'file',
	method: 'exec',
	params: ['command', 'params'],
	expect: { '': {} }
});

function delay(ms) {
	return new Promise(function(resolve) {
		setTimeout(resolve, ms);
	});
}

function labelOf(kind) {
	return kind === 'backend' ? _('后端') : _('前端');
}

function methodLabel(method) {
	return method === 'wget' ? 'wget-ssl' : 'node-fetch';
}

function errorText(err) {
	if (!err)
		return _('未知错误');
	if (typeof err === 'string')
		return err;

	return err.message || String(err);
}

function isTimeoutError(err) {
	return /timed out|timeout|超时/i.test(errorText(err));
}

function getServiceStatus() {
	return callServiceList(SERVICE).then(function(res) {
		try {
			return res[SERVICE].instances.instance1.running === true;
		} catch (e) {
			return false;
		}
	}).catch(function() {
		return false;
	});
}

function readVersion(kind) {
	return fs.read(VERSION_FILES[kind]).then(function(content) {
		return (content || '').trim();
	}).catch(function() {
		return '';
	});
}

function loadVersions() {
	return Promise.all([
		readVersion('backend'),
		readVersion('frontend')
	]).then(function(values) {
		return {
			backend: values[0],
			frontend: values[1]
		};
	});
}

function formatVersion(version) {
	if (!version || version === 'unknown')
		return _('未知');

	return (version.length > 32) ? version.substring(0, 32) + '…' : version;
}

function isServiceEnabled() {
	return uci.get('substore', 'config', 'enabled') === '1';
}

function panelUrl() {
	var port = uci.get('substore', 'config', 'frontend_port') || '3001';
	var apiPath = uci.get('substore', 'config', 'frontend_backend_path') || '/sub-store-api';
	var host = window.location.hostname;

	if (host.indexOf(':') !== -1 && host.charAt(0) !== '[')
		host = '[' + host + ']';

	var base = 'http://' + host + ':' + port;

	return base + '/?api=' + base + apiPath;
}

function injectStyles() {
	if (document.getElementById('substore-overview-styles'))
		return;

	var style = document.createElement('style');

	style.id = 'substore-overview-styles';
	style.textContent = [
		'.substore-card {',
		'  border: 1px solid var(--border-color-medium, #d5d9dd);',
		'  border-radius: 6px;',
		'  background: var(--background-color-high, #fff);',
		'  padding: 14px 16px;',
		'  margin: 0 0 16px;',
		'}',
		'.substore-head {',
		'  display: flex;',
		'  flex-wrap: wrap;',
		'  align-items: center;',
		'  justify-content: space-between;',
		'  gap: 8px 16px;',
		'}',
		'.substore-state {',
		'  display: inline-flex;',
		'  align-items: center;',
		'  gap: 8px;',
		'  font-size: 15px;',
		'}',
		'.substore-dot {',
		'  width: 9px;',
		'  height: 9px;',
		'  border-radius: 50%;',
		'  background: #9e9e9e;',
		'  flex: none;',
		'}',
		'.substore-dot.is-up { background: var(--success-color-high, #16a34a); }',
		'.substore-dot.is-down { background: var(--error-color-high, #dc2626); }',
		'.substore-dot.is-off { background: #9e9e9e; }',
		'.substore-versions {',
		'  display: inline-flex;',
		'  flex-wrap: wrap;',
		'  align-items: center;',
		'  gap: 6px;',
		'  font-size: 12px;',
		'  color: var(--text-color-low, #6b7280);',
		'}',
		'.substore-versions code {',
		'  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;',
		'  font-size: 12px;',
		'  line-height: 1.6;',
		'  padding: 0 6px;',
		'  border-radius: 4px;',
		'  background: var(--background-color-low, rgba(127, 127, 127, 0.12));',
		'}',
		'.substore-sep { opacity: 0.45; }',
		'.substore-actions {',
		'  display: flex;',
		'  flex-wrap: wrap;',
		'  gap: 8px;',
		'  margin-top: 12px;',
		'}',
		'.substore-actions .cbi-button {',
		'  margin: 0 !important;',
		'  padding: 6px 14px;',
		'  font-size: 13px;',
		'  line-height: 1.5;',
		'}',
		'.substore-msg {',
		'  margin-top: 10px;',
		'  font-size: 12px;',
		'  line-height: 1.5;',
		'  color: var(--text-color-low, #6b7280);',
		'  white-space: pre-wrap;',
		'  word-break: break-word;',
		'}',
		'.substore-msg:empty { display: none; }',
		'.substore-msg.is-ok { color: var(--success-color-high, #15803d); }',
		'.substore-msg.is-warn { color: var(--warn-color-high, #b45309); }',
		'.substore-msg.is-err { color: var(--error-color-high, #b91c1c); }',
		'@media (max-width: 600px) {',
		'  .substore-actions .cbi-button { flex: 1 1 calc(50% - 4px); }',
		'}'
	].join('\n');

	document.head.appendChild(style);
}

function setMessage(view, text, kind) {
	view.message.textContent = text || '';
	view.message.className = 'substore-msg' + (kind ? ' is-' + kind : '');
}

function updateOverview(view, running, versions) {
	var state;

	if (running)
		state = { cls: 'is-up', text: _('运行中') };
	else if (isServiceEnabled())
		state = { cls: 'is-down', text: _('已停止') };
	else
		state = { cls: 'is-off', text: _('未启用') };

	view.running = running;
	view.versions = versions;
	view.dot.className = 'substore-dot ' + state.cls;
	view.stateText.textContent = state.text;
	view.backendVer.textContent = formatVersion(versions.backend);
	view.frontendVer.textContent = formatVersion(versions.frontend);
}

function refreshOverview(view) {
	return Promise.all([
		getServiceStatus(),
		loadVersions()
	]).then(function(res) {
		updateOverview(view, res[0], res[1]);

		return res;
	});
}

function setBusy(view, buttons, busy) {
	view.busy = busy;

	for (var i = 0; i < buttons.length; i++)
		buttons[i].disabled = busy;
}

function createButton(label) {
	return E('button', {
		'class': 'cbi-button cbi-button-action',
		'type': 'button'
	}, label);
}

function buildOverview(running, versions) {
	var dot = E('span', { 'class': 'substore-dot' });
	var stateText = E('strong', {});
	var backendVer = E('code', {});
	var frontendVer = E('code', {});
	var message = E('div', { 'class': 'substore-msg' });
	var actions = E('div', { 'class': 'substore-actions' });

	var card = E('div', { 'class': 'substore-card' }, [
		E('div', { 'class': 'substore-head' }, [
			E('span', { 'class': 'substore-state' }, [ dot, stateText ]),
			E('span', { 'class': 'substore-versions' }, [
				_('后端'), backendVer,
				E('span', { 'class': 'substore-sep' }, '·'),
				_('前端'), frontendVer
			])
		]),
		actions,
		message
	]);

	var view = {
		card: card,
		actions: actions,
		message: message,
		dot: dot,
		stateText: stateText,
		backendVer: backendVer,
		frontendVer: frontendVer,
		busy: false,
		running: running,
		versions: versions
	};

	updateOverview(view, running, versions);

	return view;
}

function openPanel(view) {
	if (!isServiceEnabled()) {
		setMessage(view, _('请先启用服务并保存应用。'), 'warn');
		return;
	}

	if (!view.running) {
		setMessage(view, _('服务未运行，请先点击“重启服务”。'), 'warn');
		return;
	}

	window.open(panelUrl(), '_blank', 'noopener');
}

function restartService(view, buttons) {
	if (view.busy)
		return;

	if (!isServiceEnabled()) {
		setMessage(view, _('请先启用服务并保存应用。'), 'warn');
		return;
	}

	setBusy(view, buttons, true);
	setMessage(view, _('正在重启服务…'));

	return callInitAction(SERVICE, 'restart').then(function() {
		return delay(1500);
	}).then(function() {
		return refreshOverview(view);
	}).then(function() {
		setMessage(view, _('服务已重启。'), 'ok');
	}).catch(function(err) {
		setMessage(view, _('重启失败：%s').format(errorText(err)), 'err');
	}).finally(function() {
		setBusy(view, buttons, false);
	});
}

function updateSources() {
	var sources = [];

	if ((uci.get('substore', 'config', 'download_proxy') || '').trim() !== '')
		sources.push({ id: 'proxy', label: _('加速代理') });

	sources.push({ id: 'official', label: _('GitHub 直连') });

	return sources;
}

function runUpdateScript(kind, view) {
	var sources = updateSources();
	var method = (uci.get('substore', 'config', 'download_method') === 'wget') ? 'wget' : 'node';

	function trySource(index) {
		var source = sources[index];

		setMessage(view, _('正在通过%s更新%s（%s）…').format(
			source.label, labelOf(kind), methodLabel(method)));

		return callFileExec(UPDATE_SCRIPTS[kind], [ source.id, method ]).then(function(res) {
			var stdout = ((res && res.stdout) || '').trim();
			var stderr = ((res && res.stderr) || '').trim();
			var code = res ? res.code : -1;

			if (code === 0 && stdout === 'OK')
				return { updated: true };

			if (code === 0 && stdout.indexOf('ALREADY_LATEST:') === 0)
				return {
					updated: false,
					version: stdout.substring('ALREADY_LATEST:'.length).trim()
				};

			if (code === 0 && stdout.indexOf('DOWNLOAD_FAILED:') === 0)
				throw new Error(stdout.substring('DOWNLOAD_FAILED:'.length).trim() || _('下载失败'));

			throw new Error(stderr || stdout || _('脚本执行失败（退出码 %d）').format(code));
		}).catch(function(err) {
			if (isTimeoutError(err) || index + 1 >= sources.length)
				throw err;

			setMessage(view, _('%s更新失败（%s），改用%s重试…').format(
				labelOf(kind), errorText(err), sources[index + 1].label), 'warn');

			return trySource(index + 1);
		});
	}

	return trySource(0);
}

function verifyAfterTimeout(kind, view, beforeVersion) {
	var label = labelOf(kind);

	return delay(1500).then(function() {
		return refreshOverview(view);
	}).then(function() {
		var afterVersion = view.versions[kind];

		if (!view.running) {
			setMessage(view, _('请求超时，且服务未正常运行，请检查网络后重试。'), 'err');
		}
		else if (afterVersion && beforeVersion && afterVersion !== beforeVersion) {
			setMessage(view, _('请求超时，但%s已在后台更新至 %s。').format(
				label, formatVersion(afterVersion)), 'ok');
		}
		else {
			setMessage(view, _('请求超时，暂时无法确认%s是否已更新，当前版本：%s。').format(
				label, formatVersion(afterVersion)), 'warn');
		}
	});
}

function updateComponent(kind, view, buttons) {
	if (view.busy)
		return;

	if (!isServiceEnabled()) {
		setMessage(view, _('请先启用服务并保存应用。'), 'warn');
		return;
	}

	var beforeVersion = view.versions[kind];

	setBusy(view, buttons, true);

	return runUpdateScript(kind, view).then(function(res) {
		return refreshOverview(view).then(function() {
			if (res.updated) {
				setMessage(view, _('%s已更新完成。').format(labelOf(kind)), 'ok');
				return;
			}

			var latest = res.version || view.versions[kind];

			setMessage(view, latest
				? _('当前已是最新版本（%s），无需更新。').format(formatVersion(latest))
				: _('当前已是最新版本，无需更新。'), 'ok');
		});
	}).catch(function(err) {
		if (isTimeoutError(err))
			return verifyAfterTimeout(kind, view, beforeVersion);

		return refreshOverview(view).then(function() {
			setMessage(view, _('%s更新失败：%s').format(labelOf(kind), errorText(err)), 'err');
		});
	}).finally(function() {
		setBusy(view, buttons, false);
	});
}

return view.extend({
	load: function() {
		return Promise.all([
			uci.load('substore'),
			getServiceStatus(),
			loadVersions()
		]);
	},

	render: function(data) {
		var m, s, o;

		m = new form.Map('substore', _('Sub-Store'), _('订阅管理服务的运行状态与基础配置'));

		s = m.section(form.NamedSection, 'config', 'substore', _('基础配置'));
		s.anonymous = true;
		s.tab('general', _('常规'));
		s.tab('display', _('实例显示'));
		s.tab('recovery', _('数据恢复'));

		o = s.taboption('general', form.Flag, 'enabled', _('启用服务'), _('关闭后服务停止，保存并应用生效'));
		o.rmempty = false;

		o = s.taboption('general', form.Value, 'data_dir', _('数据目录'), _('订阅、脚本和配置数据的存放目录'));
		o.default = '/etc/sub-store';
		o.placeholder = '/etc/sub-store';
		o.rmempty = false;

		o = s.taboption('general', form.Value, 'frontend_backend_path', _('后端路径前缀'), _('后端 API 使用的路径，建议只使用字母、数字、短横线和下划线'));
		o.default = '/sub-store-api';
		o.placeholder = 'sub-store-api';
		o.rmempty = false;
		o.cfgvalue = function(section_id) {
			var value = uci.get('substore', section_id, 'frontend_backend_path') || '/sub-store-api';
			return value.replace(/^\/+/, '');
		};
		o.write = function(section_id, value) {
			var path = (value || '').trim().replace(/^\/+/, '').replace(/\/+$/, '');

			uci.set('substore', section_id, 'frontend_backend_path', path ? '/' + path : '/sub-store-api');
		};

		o = s.taboption('display', form.Value, 'backend_custom_name', _('实例名称'), _('显示在 Sub-Store 前端实例列表中的名称'));
		o.placeholder = 'OpenWrt';

		o = s.taboption('display', form.Value, 'backend_custom_icon', _('实例图标 URL'), _('显示在前端实例列表中的图标地址'));
		o.placeholder = 'https://example.com/icon.png';

		o = s.taboption('recovery', form.Value, 'data_url', _('远程数据地址'), _('服务启动时从此地址拉取并恢复数据，留空则不启用'));
		o.placeholder = 'https://gist.githubusercontent.com/user/id/raw/Sub-Store';

		o = s.taboption('recovery', form.Value, 'data_url_post', _('拉取后执行'), _('数据拉取成功后执行的 JS 表达式'));
		o.placeholder = "content.settings.gistToken='your_token'";

		return m.render().then(function(node) {
			injectStyles();

			var overview = buildOverview(data[1], data[2]);
			var buttons = [
				createButton(_('打开面板')),
				createButton(_('重启服务')),
				createButton(_('更新后端')),
				createButton(_('更新前端'))
			];

			buttons[0].addEventListener('click', function() {
				openPanel(overview);
			});
			buttons[1].addEventListener('click', function() {
				restartService(overview, buttons);
			});
			buttons[2].addEventListener('click', function() {
				updateComponent('backend', overview, buttons);
			});
			buttons[3].addEventListener('click', function() {
				updateComponent('frontend', overview, buttons);
			});

			for (var i = 0; i < buttons.length; i++)
				overview.actions.appendChild(buttons[i]);

			var anchor = node.querySelector('.cbi-section');

			if (anchor)
				node.insertBefore(overview.card, anchor);
			else
				node.appendChild(overview.card);

			var poll = setInterval(function() {
				if (!document.body.contains(overview.card)) {
					clearInterval(poll);
					return;
				}

				if (!overview.busy)
					refreshOverview(overview);
			}, 15000);

			return node;
		});
	}
});
