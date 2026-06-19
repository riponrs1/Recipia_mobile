const express = require('express');
const path = require('path');
const fs = require('fs');

const app = express();
const PORT = 8000;
const ROOT_DIR = path.resolve(__dirname, '..'); // Parent directory is the root

app.use(express.static('public'));

// API to list files
app.get('/api/files', (req, res) => {
    const dirPath = req.query.path || '';
    const fullPath = path.join(ROOT_DIR, dirPath);

    // Security check to prevent escaping root
    if (!fullPath.startsWith(ROOT_DIR)) {
        return res.status(403).json({ error: 'Access denied' });
    }

    fs.readdir(fullPath, { withFileTypes: true }, (err, files) => {
        if (err) {
            return res.status(500).json({ error: 'Unable to scan directory' });
        }

        const fileList = files.map(file => {
            const filePath = path.join(fullPath, file.name);
            let size = 0, mtime = null;
            try {
                const stat = fs.statSync(filePath);
                size = stat.size;
                mtime = stat.mtime;
            } catch(e) {}
            return {
                name: file.name,
                isDirectory: file.isDirectory(),
                path: path.join(dirPath, file.name),
                size,
                mtime
            };
        });

        res.json({ path: dirPath, files: fileList });
    });
});

// Serve files for download
app.get('/download', (req, res) => {
    const filePath = req.query.path;
    if (!filePath) return res.status(400).send('Missing path');

    const fullPath = path.join(ROOT_DIR, filePath);

    // Security check
    if (!fullPath.startsWith(ROOT_DIR)) {
        return res.status(403).send('Access denied');
    }

    res.download(fullPath);
});

app.listen(PORT, '0.0.0.0', () => {
    console.log(`Downloader running at http://0.0.0.0:${PORT}`);
    const { networkInterfaces } = require('os');
    const nets = networkInterfaces();
    for (const name of Object.keys(nets)) {
        for (const net of nets[name]) {
            if (net.family === 'IPv4' && !net.internal) {
                console.log(`On Network: http://${net.address}:${PORT}`);
            }
        }
    }
});
