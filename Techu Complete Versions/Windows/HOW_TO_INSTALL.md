# Techuboard for Windows

## 🪟 Windows সংস্করণ পরিচিতি
Techuboard Windows-এর জন্য একটি আধুনিক, লাইটওয়েট এবং ব্যাকগ্রাউন্ড ট্রে-সাপোর্টেড ডেক্সটপ অ্যাপ।

### 🛠️ রিলিজ প্যাকেজ তৈরির নিয়ম (Zero Cost CI/CD)
Windows-এর নেটিভ C++ ও MSVC বাইনারি তৈরি করার জন্য গিটহাব অ্যাকশনস (GitHub Actions) বিল্ট-ইন কনফিগার করা আছে:
1. রিপোজিটরিতে `v1.0.0` ট্যাগ পুশ করলেই গিটহাবের Windows সার্ভার স্বয়ংক্রিয়ভাবে `Techuboard-Windows-x64-v1.0.0.zip` তৈরি করে দেবে।
2. ফাইলটি আনজিপ করে `Techuboard.exe` ডাবল-ক্লিক করলেই উইন্ডোজে সরাসরি রান করবে (কোনো এক্সট্রা ইনস্টলেশন ঝামেলা ছাড়াই পোর্টেবল হিসেবে চলে)।

### 💻 নিজস্ব উইন্ডোজ পিসি থেকে সরাসরি বিল্ড করতে চাইলে:
```powershell
cd clipy_android
flutter build windows --release -t lib/main_windows.dart
./scripts/package_windows.ps1 -Version 1.0.0
```
আউটপুট জিপ ফাইলটি `dist/Techuboard-Windows-x64-v1.0.0.zip` এ জমা হবে।
