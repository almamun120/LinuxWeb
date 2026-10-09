<?php $ext = get_loaded_extensions(); sort($ext); ?>
<!doctype html><meta charset="utf-8"><title>LSRV</title>
<style>body{font:16px system-ui;max-width:760px;margin:3rem auto;padding:0 1rem}code{background:#eee;padding:2px 5px;border-radius:4px}</style>
<h1>LSRV OK ✔</h1>
<p>PHP <b><?= PHP_VERSION ?></b> · protocol <b><?= htmlspecialchars($_SERVER['SERVER_PROTOCOL']) ?></b> · HTTPS: <b><?= !empty($_SERVER['HTTPS']) ? 'yes' : 'no' ?></b></p>
<p>Document root: <code><?= htmlspecialchars($_SERVER['DOCUMENT_ROOT']) ?></code></p>
<details><summary>PHP extensions (<?= count($ext) ?>)</summary><?= implode(', ', $ext) ?></details>
