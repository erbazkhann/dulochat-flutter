DULOCHAT FLUTTER APP (Part 1)

Part 1 ka kaam: app ban jaye, phone mein install ho, aur tumhare server se baat kar sake.
Server ka address lib/config.dart mein ek hi line mein hai.

APK GitHub par banta hai (phone par nahi):
1. github.com par free account banao, naya Private repo banao: dulochat-flutter
2. Is poore folder ko repo mein upload karo (Termux commands neeche).
3. Repo > Actions > "Build Dulochat APK" > Run workflow. Pehli baar 8-12 minute lagte hain.
4. Hara tick aane par us run ke andar "Dulochat-APK" download karo (zip), andar app-debug.apk hai.
5. Phone mein install karo (Unknown sources allow karna padta hai).
6. App kholkar "Check server" dabao. Hara likha aaye to Part 1 pass.

Termux se upload:
  pkg install git
  cd <jahan folder hai>/dulochat-flutter
  git init && git add . && git commit -m "part 1"
  git branch -M main
  git remote add origin https://github.com/TUMHARA_USERNAME/dulochat-flutter.git
  git push -u origin main
(Password ki jagah GitHub ka Personal Access Token: GitHub > Settings > Developer settings > Tokens.)

Build fail ho to Actions mein us run ka error text copy karke bhej do.
