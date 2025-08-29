/**
 * app.js
 * 
 * SSH公開鍵をLDAPに追加/削除するための簡易Web UI
 * - Express サーバー
 * - kinit による認証
 * - ldapsearch/ldapmodifyによるLDAP操作
 * - フロントエンドで鍵の追加/削除を行うUIを提供
 */

const express = require('express');
const { spawnSync } = require('child_process');
const app = express();
const port = 3000;
const router = express.Router();

// Passenger (Phusion Passenger) 環境ではBASEパスを考慮
const BASE = process.env.PASSENGER_BASE_URI || '/';

// POSTフォームのbodyをパース
app.use(express.urlencoded({ extended: true }));
app.use(BASE, router);

/**
 * HTMLエスケープ用関数
 * 出力をそのままHTMLに埋め込むときのXSS対策
 */
const esc = (s) =>
  String(s)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

/**
 * LDIF形式の文字列をパースし、uidとipaSshPubKeyを抽出
 */
function parseLdif(ldif) {
  const text = String(ldif || '');
  const firstBlock = text.split(/\n\s*\n/).find(Boolean) || '';
  const lines = firstBlock.split('\n');
  const out = { uid: [], ipaSshPubKey: [] };

  for (let raw of lines) {
    const m = raw.match(/^([\w;.-]+):\s*(.*)$/);
    if (!m) continue;
      
    const key = m[1];
    const val = m[2];
    if (key === 'uid') out.uid.push(val);
    else if (key === 'ipaSshPubKey') out.ipaSshPubKey.push(val);
  }
  return out;
}

/**
 * 共通 HTML ヘッダ部分
 */
const HTML_HEAD = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>SSH Public Key</title>
  <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">
</head>`;

/**
 * 初期ページ (ログインフォーム)
 */
router.get('/', (req, res) => {
  res.send(`${HTML_HEAD}
  <body class="bg-light">
    <div class="container py-4">
      <h1 class="mb-4">SSH Public Key</h1>
      <form action="${BASE}/login" method="post" autocomplete="off" class="row gy-3">
        <div class="col-12 col-md-6">
          <label for="password" class="form-label">Password</label>
          <input type="password" id="password" name="password" required class="form-control">
        </div>
        <div class="col-12">
          <button type="submit" class="btn btn-primary">Submit</button>
        </div>
      </form>
    </div>
  </body>
</html>`);
});

/**
 * 認証処理
 * - kinit で Kerberos 認証
 * - ldapsearch で uid / ssh 公開鍵を取得
 * - HTML に鍵一覧と追加フォームを表示
 */
router.post('/login', (req, res) => {
  const password = req.body && req.body.password;
  if (!password) return res.status(400).send('Password is required.');

  // kinit 認証
  const ki = spawnSync('/usr/bin/kinit', [], { input: password + '\n', timeout: 15000 });
  if (ki.status !== 0) {
    return res.status(401).send(`<h1 class="text-danger">Login failed</h1><a href="${BASE}">Back</a>`);
  }

  // ユーザー名を取得
  const USERNAME = process.env.USER || process.env.LOGNAME || 'unknown';
  const filter = `(krbPrincipalName=${USERNAME}@CLOUD.R-CCS.RIKEN.JP)`;
  const attrs = ['uid', 'ipaSshPubKey'];

  // ldapsearch 実行
  const args = ['-LLL', '-Y', 'GSSAPI', '-o', 'ldif-wrap=no', filter, ...attrs];
  const ls = spawnSync('/usr/bin/ldapsearch', args, { timeout: 15000 });
  if (ls.status !== 0) {
    return res.status(500).send(`<pre>${esc((ls.stderr || '').toString())}</pre>`);
  }

  // LDIF をパース
  const parsed = parseLdif((ls.stdout || '').toString());
  const uidHtml = parsed.uid.length
    ? parsed.uid.map(v => `<code>${esc(v)}</code>`).join('<br>')
    : '—';
  const keysArr = parsed.ipaSshPubKey.length ? parsed.ipaSshPubKey : [];

  // HTML 出力
  res.send(`${HTML_HEAD}
  <body class="bg-light">
    <div class="container py-4">
      <h1>SSH Public Key</h1>
      <div class="row g-3 mb-1">
        <div id="uid-values">uid : ${uidHtml}</div>
      </div>
      <div class="card w-75 border-secondary">
        <div class="card-body">
          <h5>Registered Keys</h5>
          <div class="table-responsive">
            <table class="table table-striped table-bordered border-secondary">
              <tbody id="keys-tbody"></tbody>
            </table>
          </div>
          <h5 class="mt-3">Add Key</h5>
          <div class="input-group">
            <input type="text" id="newKey" class="form-control border-secondary" placeholder="(Enter new SSH public key)">
            <button type="button" class="btn btn-success" onclick="addKey()">Add</button>
          </div>
        </div>
      </div>
      <div>
        It may take up to 60 seconds for the settings to take effect.
      </div>
      <div class="mt-2">
        <a href="${BASE}">Back</a>
      </div>
    </div>

    <script>
      const BASE = "${BASE}";
      window.sshKeys = ${JSON.stringify(keysArr)};

      // HTML エスケープ
      function escapeHtml(s) {
        return s.replace(/&/g,'&amp;')
                .replace(/</g,'&lt;')
                .replace(/>/g,'&gt;');
      }

      // uid を DOM から取得
      function getUid() {
        let uidNode = document.querySelector('#uid-values code');
        return uidNode ? uidNode.textContent.trim() : '';
      }

      // テーブル描画
      window.renderTable = function() {
        let tbody = document.getElementById('keys-tbody');
        if (!tbody) return;

        if (!Array.isArray(window.sshKeys) || window.sshKeys.length === 0) {
          tbody.innerHTML = '<tr><td colspan="3" class="text-center text-muted">No SSH public keys</td></tr>';
          return;
        }

        let rows = window.sshKeys.map((k, i) => 
          '<tr id="row-' + i + '">' +
            '<td class="align-middle"><div class="text-monospace small text-wrap text-break">' + escapeHtml(k) + '</div></td>' +
            '<td class="align-middle">' +
              '<button type="button" class="btn btn-sm btn-outline-danger" title="Delete this key" onclick="removeKey(' + i + ')">Delete</button>' +
            '</td>' +
          '</tr>'
        ).join('');

        tbody.innerHTML = rows;
      };

      // 鍵削除
      window.removeKey = function(i) {
        if (!Array.isArray(window.sshKeys) || i < 0 || i >= window.sshKeys.length) return;
        let uid = getUid();
        let key = window.sshKeys[i];
        if (!uid || !key) { alert('uid or key not found'); return; }

        let preview = (key.length > 120 ? key.slice(0, 120) + '...' : key);
        if (!window.confirm('Are you sure you want to delete this SSH public key? ' + preview)) return;

        fetch(BASE + '/delete-key', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ uid, key })
        })
        .then(async r => {
          let text = await r.text();
          if (!r.ok) { alert('Delete failed: ' + text); return; }
          window.sshKeys.splice(i, 1);
          window.renderTable();
        })
        .catch(e => alert('Delete error: ' + e));
      };

      // 鍵追加
      window.addKey = function() {
        let inp = document.getElementById('newKey');
        let val = inp.value.trim();
        let uid = getUid();
        if (!uid || !val) { alert('uid or key not found'); return; }

        fetch(BASE + '/add-key', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ uid, key: val })
        })
        .then(r => r.text())
        .then(() => {
          window.sshKeys.push(val);
          inp.value = '';
          window.renderTable();
        })
        .catch(e => alert('Add error: ' + e));
      };

      // 初期描画
      document.addEventListener('DOMContentLoaded', window.renderTable);
    </script>
  </body>
</html>`);
});

/**
 * 公開鍵追加/削除処理を共通化
 */
const handleKey = (action) => (req, res) => {
  const uid = (req.body.uid || '').trim();
  const key = (req.body.key || '').trim();
  if (!uid || !key) return res.status(400).send('uid and key required');

  const dn = `uid=${uid},cn=users,cn=accounts,dc=cloud,dc=r-ccs,dc=riken,dc=jp`;
  const uri = 'ldap://ds1.cloud.r-ccs.riken.jp';
  const ldif =
    `dn: ${dn}\nchangetype: modify\n${action}: ipaSshPubKey\nipaSshPubKey: ${key}\n`;

  const mod = spawnSync('/usr/bin/ldapmodify',
    ['-ZZ', '-Y', 'GSSAPI', '-H', uri],
    { input: ldif, timeout: 15000 }
  );

  if (mod.status === 0) return res.send('ok');
  return res.status(500).send((mod.stderr || '').toString());
};

// API エンドポイント
router.post('/add-key', express.json(), handleKey('add'));
router.post('/delete-key', express.json(), handleKey('delete'));

// サーバー起動
app.listen(port, () => {
  console.log(`Server running at http://localhost:${port}`);
});
