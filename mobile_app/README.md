# Haroon Tailor - Separate Mobile App (Client / Owner App)

Yeh mobile app ekdam alag banayi gayi hai. Isse aapke main desktop/web system me koi bhi badlaav nahi hua hai.

## Is Mobile App Me Kya Kya Shamil Hai:
1. **Grahak (Customers)**:
   - Grahak list aur mobile / naam se instant search.
   - Naya grahak add karein: 10-digit duplicate number check (agar number pehle se exist karta hai toh turant warning aur block).
2. **Orders & Deliveries**:
   - Sabhi orders ki list, pending aur delivered status filter.
   - Deliveries dashboard (partial delivery confirmation ke saath).
   - Order details aur WhatsApp invoice receipt link.
3. **Naya Order (New Order)**:
   - **24 Measurement Boxes** (`Box 1` se `Box 24`) mobile ke liye clean 4-column responsive grid me.
   - **Special Instructions** (har item ke liye) + **Order Instructions** mic voice dictation ke saath.
   - **Old Measurements Recall**: Purane grahak ko chunte hi unke purane naap 1-tap me auto-fill ho jaate hain.
   - **Fast Numpad**: On-screen custom keypad jisse mobile par bina keyboard glitch ke fast entry hoti hai.
   - Photo attach (Camera & Upload).
   - WhatsApp confirmation message.
4. **Dashboard KPIs**:
   - Aaj ke orders, pending deliveries, bacha hua balance.
5. **Kareegar, Stock, Expenses, Reports** is mobile app me nahi hain (yeh sab main desktop system me hi hain).

---

## Backend Connection:
Yeh mobile app direct aapke hosted server (`https://haroon-tailor.onrender.com`) se connect karti hai. Iska data seedha aapke Neon PostgreSQL database aur Cloudinary photos me sync hota hai.

---

## Android APK Kaise Banaye (Option 2):

### Tareeqa 1: PWABuilder (Sabse Aasan - 2 Minute me APK)
1. `https://www.pwabuilder.com` par jayein.
2. Hosted URL daalein ya `mobile_app` package karein.
3. "Generate Android Package (APK)" par click karein.
4. `.apk` download karke phone me install karein!

### Tareeqa 2: Capacitor / Android Studio
`mobile_app` folder ke andar:
```bash
cd mobile_app
npm install
npx cap add android
npx cap sync
npx cap open android
```
Android Studio khulne par `Build > Build Bundle(s) / APK(s) > Build APK(s)` par click karein.
APK file ready ho jayegi!
