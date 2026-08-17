/* Site uzerinden gorsel uretimi.
 *
 * Iki degisiklik yapildi:
 *  - Uretim artik hesap gerektiriyor; gunluk hak hesaba bagli.
 *  - Senkron /generate yerine asenkron /jobs kullaniliyor. Uretim
 *    ~90 saniye surdugu icin tek uzun istek tunel tarafindan
 *    kesilebiliyordu; is numarasiyla sorgulamak bunu ortadan kaldiriyor.
 */

let isGenerating = false;

async function resimUret() {
    if (isGenerating) return;

    const promptText = document.getElementById("promptInput").value.trim();
    const generateBtn = document.getElementById("generateBtn");
    const loadingDiv = document.getElementById("loadingSpinner");
    const resultImage = document.getElementById("resultImage");
    const downloadBtn = document.getElementById("downloadBtn");
    const placeholderBox = document.getElementById("placeholderBox");

    if (!EbruHesap.girisYapildiMi()) {
        alert("Eser üretmek için giriş yapman gerekiyor.");
        location.href = "/giris";
        return;
    }

    if (!promptText) {
        alert("Nasıl bir eser istediğini yaz.");
        return;
    }

    isGenerating = true;
    generateBtn.disabled = true;
    generateBtn.innerText = "Hazırlanıyor...";

    if (placeholderBox) placeholderBox.classList.add("hidden");
    if (loadingDiv) loadingDiv.classList.remove("hidden");
    if (resultImage) resultImage.classList.add("hidden");
    if (downloadBtn) downloadBtn.classList.add("hidden");

    try {
        const isKaydi = await isOlustur(promptText);
        const sonuc = await sonucuBekle(isKaydi.job_id, generateBtn);

        resultImage.src = sonuc.image;
        resultImage.onload = function () {
            loadingDiv.classList.add("hidden");
            resultImage.classList.remove("hidden");
            downloadBtn.classList.remove("hidden");
        };

        downloadBtn.onclick = function () {
            const link = document.createElement("a");
            link.href = resultImage.src;
            link.download = "ebru-eseri.png";
            document.body.appendChild(link);
            link.click();
            document.body.removeChild(link);
        };
    } catch (hata) {
        alert(hata.message);
        loadingDiv.classList.add("hidden");
        if (placeholderBox) placeholderBox.classList.remove("hidden");
    } finally {
        isGenerating = false;
        generateBtn.disabled = false;
        generateBtn.innerText = "ESERİ OLUŞTUR";
    }
}

/* Uretimi kuyruga alir, is numarasini doner. */
async function isOlustur(promptText) {
    const cevap = await fetch("/jobs", {
        method: "POST",
        headers: EbruHesap.basliklar(),
        body: JSON.stringify({
            prompt: promptText,
            aspect_ratio: 1.0,
        }),
    });

    const veri = await cevap.json();

    if (cevap.status === 401) {
        EbruHesap.temizle();
        throw new Error("Oturumun sona ermiş. Tekrar giriş yap.");
    }
    if (!cevap.ok) {
        throw new Error(veri.message || "Üretim başlatılamadı.");
    }
    return veri;
}

/* Is bitene kadar sorgular, ilerlemeyi butona yazar. */
async function sonucuBekle(jobId, generateBtn) {
    const bitis = Date.now() + 15 * 60 * 1000;

    while (Date.now() < bitis) {
        await new Promise((r) => setTimeout(r, 3000));

        let cevap;
        try {
            cevap = await fetch("/jobs/" + jobId, {
                headers: EbruHesap.basliklar(),
            });
        } catch (e) {
            // Gecici ag hatasi uretimi iptal etmesin.
            continue;
        }

        if (cevap.status === 404) {
            throw new Error("Bu üretimin kaydı sunucuda kalmamış.");
        }

        const veri = await cevap.json();

        if (veri.job_status === "done") {
            return veri;
        }
        if (veri.job_status === "error") {
            throw new Error(veri.message || "Üretim tamamlanamadı.");
        }

        const yuzde = Math.round((veri.progress || 0) * 100);
        if (veri.queue_length > 1) {
            generateBtn.innerText = "Sırada bekleniyor...";
        } else if (yuzde > 0) {
            generateBtn.innerText = "Çiziliyor... %" + yuzde;
        } else {
            generateBtn.innerText = "Çiziliyor...";
        }
    }

    throw new Error("Üretim çok uzun sürdü. Lütfen tekrar dene.");
}
