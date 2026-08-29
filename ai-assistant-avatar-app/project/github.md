repo: xjanova/BrainX
branch: main
path: BrainX.Client/wwwroot/universe

## Last sync
date: 2026-08-29T12:19:48Z

### Updated in this project
- อ่านส่วน "Mind avatar" (VRM, moods, lip-sync, กล้อง bust/full) เป็นฐานการออกแบบ
- ยกภาษาภาพจาก assistant-window.html: พื้นน้ำเงินเข้ม, กระจกเบลอ, ฟองคำพูดมีหาง, สีเขียว wire
- ยกระบบอารมณ์/ท่าทาง (neutral/happy/pleased/thinking/sorry) และ mic th-TH มาใช้ใน UI มือถือ
- สร้าง Mind Android.dc.html — 8 หน้าจอ Android

## Screen map
| หน้าจอ | อ้างอิงจากไฟล์ในรีโป |
|---|---|
| 1a หน้าหลัก (อวาตาร์ + แชทกระจก) | wwwroot/universe/assistant-window.html, avatar.js |
| 1b สายเข้า / 1c โทรออก | assistant-window.html (mic, bubble), BrainX.Mcp/Program.Speak.cs |
| 1d เมล / 1e ปฏิทิน / 1f ไทม์ไลน์ | README (brain tools, auto-journal) |
| 1g ตั้งค่าบุคลิก/เสียง | assistant-window.html (self_/particle, greeting), avatar/clips.json |
| 1h Always-on | avatar.js (framing bust/full), AvatarPackService.cs |
