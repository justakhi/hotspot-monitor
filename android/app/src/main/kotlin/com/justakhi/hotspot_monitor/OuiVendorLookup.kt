package com.justakhi.hotspot_monitor

data class VendorInfo(
    val vendor: String,
    val isRandomized: Boolean
)

object OuiVendorLookup {
    private val ouiMap = mapOf(
        // Apple
        "00:03:93" to "Apple", "00:1C:B3" to "Apple", "04:0C:CE" to "Apple",
        "14:10:9F" to "Apple", "24:A0:74" to "Apple", "28:CF:E9" to "Apple",
        "34:15:9E" to "Apple", "3C:15:C2" to "Apple", "40:6C:8F" to "Apple",
        "44:D8:84" to "Apple", "54:26:96" to "Apple", "60:03:08" to "Apple",
        "68:96:7B" to "Apple", "70:56:81" to "Apple", "7C:6D:62" to "Apple",
        "88:66:5A" to "Apple", "98:01:A7" to "Apple", "A4:83:E7" to "Apple",
        "AC:BC:32" to "Apple", "B8:E8:56" to "Apple", "C8:2A:14" to "Apple",
        "D0:23:DB" to "Apple", "DC:2B:2A" to "Apple", "E0:B9:BA" to "Apple",
        "F0:18:98" to "Apple", "F4:5C:89" to "Apple",
        // Samsung
        "00:12:FB" to "Samsung", "00:16:32" to "Samsung", "08:D4:2B" to "Samsung",
        "10:1D:C0" to "Samsung", "18:3A:2D" to "Samsung", "24:4B:81" to "Samsung",
        "30:CD:A7" to "Samsung", "38:01:95" to "Samsung", "48:44:F7" to "Samsung",
        "50:CC:F8" to "Samsung", "5C:0A:5B" to "Samsung", "6C:2F:2C" to "Samsung",
        "78:47:1D" to "Samsung", "84:25:DB" to "Samsung", "94:35:0A" to "Samsung",
        "A0:82:1F" to "Samsung", "B4:EF:39" to "Samsung", "C0:BD:D1" to "Samsung",
        "CC:07:AB" to "Samsung", "D0:22:BE" to "Samsung", "E4:7C:F9" to "Samsung",
        "F4:09:D8" to "Samsung",
        // Xiaomi / Redmi / POCO
        "00:9E:C8" to "Xiaomi", "0C:1D:AF" to "Xiaomi", "14:F6:5A" to "Xiaomi",
        "28:6C:07" to "Xiaomi", "34:CE:00" to "Xiaomi", "38:A4:ED" to "Xiaomi",
        "50:64:2B" to "Xiaomi", "58:44:98" to "Xiaomi", "64:09:80" to "Xiaomi",
        "68:DF:DD" to "Xiaomi", "74:23:44" to "Xiaomi", "7C:1D:D9" to "Xiaomi",
        "8C:BE:BE" to "Xiaomi", "98:FA:E3" to "Xiaomi", "AC:C1:EE" to "Xiaomi",
        "C4:0B:CB" to "Xiaomi", "D4:97:0B" to "Xiaomi", "E0:80:6B" to "Xiaomi",
        "F0:B4:29" to "Xiaomi", "F8:A4:5F" to "Xiaomi",
        // Google
        "00:1A:11" to "Google", "3C:5A:B4" to "Google", "54:60:09" to "Google",
        "94:EB:2C" to "Google", "A4:77:33" to "Google", "D8:6C:63" to "Google",
        "F4:F5:D8" to "Google", "F8:8F:CA" to "Google",
        // OnePlus / OPPO / Realme / Vivo
        "A0:91:A2" to "OnePlus", "C0:EE:FB" to "OnePlus", "AC:37:43" to "HTC/OnePlus",
        "1C:77:F6" to "OPPO", "2C:5B:B8" to "OPPO", "8C:0E:E3" to "OPPO",
        "A4:3B:FA" to "OPPO", "E8:BB:A8" to "OPPO", "F4:4E:05" to "Vivo",
        "9C:65:F9" to "Realme",
        // Huawei / Honor
        "00:E0:FC" to "Huawei", "24:69:A5" to "Huawei", "48:46:FB" to "Huawei",
        "70:72:3C" to "Huawei", "88:28:B3" to "Huawei", "AC:E2:15" to "Huawei",
        "E0:24:7F" to "Huawei",
        // PC / Chipsets / Gaming / IoT
        "00:1B:21" to "Intel", "3C:97:0E" to "Intel", "48:51:B7" to "Intel",
        "68:05:CA" to "Intel", "7C:7A:91" to "Intel", "A4:4C:C8" to "Intel",
        "D8:FC:93" to "Intel", "E8:B1:FC" to "Intel", "F0:77:C3" to "Intel",
        "00:E0:4C" to "Realtek", "48:5D:60" to "Realtek", "80:1F:02" to "Realtek",
        "18:FE:34" to "Espressif", "24:0A:C4" to "Espressif", "30:AE:A4" to "Espressif",
        "00:50:F2" to "Microsoft", "28:18:78" to "Microsoft", "7C:1E:52" to "Microsoft",
        "00:1D:D8" to "Microsoft", "B8:27:EB" to "Raspberry Pi", "DC:A6:32" to "Raspberry Pi",
        "E4:5F:01" to "Raspberry Pi", "18:65:90" to "Apple",
        "00:17:AB" to "Nintendo", "7C:BB:8A" to "Nintendo", "98:B6:E9" to "Nintendo",
        "00:04:1F" to "Sony", "F8:46:1C" to "Sony",
        "50:C7:BF" to "TP-Link", "B0:BE:76" to "TP-Link",
        "F0:27:2D" to "Amazon", "74:C2:46" to "Amazon", "68:37:E9" to "Amazon"
    )

    fun lookup(mac: String?): VendorInfo {
        if (mac.isNullOrBlank()) {
            return VendorInfo(vendor = "Unknown", isRandomized = false)
        }
        val normalized = mac.trim().uppercase()
        val parts = normalized.split(":")
        if (parts.size < 3) {
            return VendorInfo(vendor = "Unknown", isRandomized = false)
        }

        val firstByte = parts[0].toIntOrNull(16) ?: 0
        val isRandomized = (firstByte and 0x02) != 0

        val prefix = "${parts[0]}:${parts[1]}:${parts[2]}"
        val matched = ouiMap[prefix]
        val vendor = when {
            matched != null -> matched
            isRandomized -> "Private / Randomized MAC"
            else -> "Unknown ($prefix)"
        }
        return VendorInfo(vendor = vendor, isRandomized = isRandomized)
    }
}
