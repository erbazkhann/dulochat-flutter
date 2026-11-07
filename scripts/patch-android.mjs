// Adds the Android permissions and the app name. No dependencies.
import fs from 'node:fs';
const f = 'android/app/src/main/AndroidManifest.xml';
let x = fs.readFileSync(f, 'utf8');
const perms = ['INTERNET', 'CAMERA', 'RECORD_AUDIO', 'MODIFY_AUDIO_SETTINGS', 'POST_NOTIFICATIONS', 'VIBRATE', 'WAKE_LOCK'];
let add = '';
for (const p of perms) if (!x.includes('android.permission.' + p + '"')) add += '    <uses-permission android:name="android.permission.' + p + '" />\n';
if (add) x = x.replace('<application', add + '    <application');
x = x.replace(/android:label="[^"]*"/, 'android:label="Dulochat"');
fs.writeFileSync(f, x);
console.log('manifest ok');
