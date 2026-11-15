const express = require('express');
const path = require('path');
const fs = require('fs');

const app = express();
const PORT = 8000;
const APK_NAME = 'recipia-debug.apk';
const APK_PATH = path.join(__dirname, 'public', APK_NAME);

app.use(express.static(path.join(__dirname, 'public')));

// Expose only the installable APK, not the rest of the mobile project.
app.get('/api/files', (req, res) => {
    fs.stat(APK_PATH, (err, stat) => {
        if (err) return res.status(404).json({ error: 'APK not found' });
        res.json({
            path: '',
            projectName: 'Recipia',
            files: [{
                name: APK_NAME,
                isDirectory: false,
                path: APK_NAME,
                size: stat.size,
                mtime: stat.mtime
            }]
        });
    });
});

app.get('/download', (req, res) => {
    if (req.query.path !== APK_NAME) return res.sendStatus(404);
    res.download(APK_PATH, APK_NAME);
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
