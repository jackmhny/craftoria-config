#!/usr/bin/env bash
set -euo pipefail

WEBPAGE=/var/www/mc/backups/index.html

# Start HTML + styling (white on black, monospace, centered)
cat > "$WEBPAGE" <<'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Craftoria Backups</title>
  <style>
    html, body {
      background: #000;
      color: #fff;
      font-family: 'SFMono-Regular', Consolas, 'Liberation Mono', Menlo, Courier, monospace;
      margin: 0;
      padding: 0;
      height: 100%;
    }
    body {
      display: flex;
      flex-direction: column;
      align-items: center;
      padding: 2rem;
    }
    header {
      text-align: center;
      margin-bottom: 2rem;
    }
    header h1 {
      font-size: 2.5rem;
      margin: 0;
      letter-spacing: 0.1em;
    }
    header p {
      margin: 0.5rem 0;
      opacity: 0.8;
    }
    table {
      border-collapse: collapse;
      width: 100%;
      max-width: 900px;
    }
    thead th {
      border-bottom: 1px solid #fff;
      padding: 0.5rem 1rem;
      text-align: left;
    }
    tbody tr:nth-child(odd) {
      background: rgba(255,255,255,0.05);
    }
    td {
      padding: 0.5rem 1rem;
    }
    footer {
      margin-top: 2rem;
      font-size: 0.8rem;
      opacity: 0.6;
    }
  </style>
</head>
<body>
  <header>
    <h1>Craftoria Backups</h1>
    <p>Automated backup summary</p>
  </header>
  <table>
    <thead>
      <tr>
        <th>Archive</th>
        <th>Original</th>
        <th>Compressed</th>
        <th>Deduplicated</th>
      </tr>
    </thead>
    <tbody>
HTML

# Loop through archives and emit table rows
borg list --format="{archive}{NEWLINE}" | while IFS= read -r archive; do
  borg info "::${archive}" | awk -v arch="$archive" '
    /This archive:/ {
      orig   = $(NF-5) " " $(NF-4)
      comp   = $(NF-3) " " $(NF-2)
      dedup  = $(NF-1) " " $NF
      printf "      <tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>\n", arch, orig, comp, dedup
    }
  '
done >> "$WEBPAGE"

# Close out the HTML
cat >> "$WEBPAGE" <<HTML
    </tbody>
  </table>
  <footer>
    Generated on $(date +"%Y-%m-%d %H:%M:%S") | <a href="https://mc.jackmhny.xyz" style="color: #aaa; text-decoration: underline;">Home</a>
  </footer>
</body>
</html>
HTML

# Permissions
chmod 644 "$WEBPAGE"
chown root:www-data "$WEBPAGE"

# Git commit hook to sync the HTML page
echo "Syncing backup page to git repository..."

# Add the updated file to git
git --git-dir=/.config-repo.git --work-tree=/ add "$WEBPAGE"

# Create a commit with timestamp
git --git-dir=/.config-repo.git --work-tree=/ commit -m "Update backup page: $(date +"%Y-%m-%d %H:%M:%S")" --quiet || echo "No changes to commit"

git --git-dir=/.config-repo.git --work-tree=/ push origin master

echo "Git sync complete"
