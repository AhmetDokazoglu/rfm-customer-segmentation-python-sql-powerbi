# ============================================================
# RFM PROJESİ - PYTHON VERİ ÖN İŞLEME (ONLINE RETAIL II)
# Çıktı: SQL Server'a aktarılmaya hazır temiz CSV
# ============================================================

import pandas as pd


############################ 1) Veri Yükleme ############################
# Not: Dosya adını/path'ini kendi bilgisayarına göre düzenle.
dosya_yolu = r"Online Retail II.xlsx"
df_2009_2010 = pd.read_excel(dosya_yolu, sheet_name="Year 2009-2010")
df_2010_2011 = pd.read_excel(dosya_yolu, sheet_name="Year 2010-2011")
df = pd.concat([df_2009_2010, df_2010_2011], ignore_index=True)




############################ 2) Kolon isimlerini düzenleme ############################

# Orijinal kolonlar genelde: Invoice, StockCode, Description, Quantity, InvoiceDate, Price, Customer ID, Country
# (Bazı dosyalarda "CustomerID" olarak da gelebilir.)
df.columns = [c.strip() for c in df.columns]
rename_map = {
    "Invoice": "FaturaNo",
    "StockCode": "UrunKodu",
    "Description": "UrunAciklama",
    "Quantity": "Adet",
    "InvoiceDate": "FaturaTarihi",
    "Price": "BirimFiyat",
    "Customer ID": "MusteriID",
    "CustomerID": "MusteriID",
    "Country": "Ulke"
}
df = df.rename(columns={k: v for k, v in rename_map.items() if k in df.columns})
# Gerekli kolonlar var mı kontrol (basit güvenlik)
gerekli = ["FaturaNo", "UrunKodu", "UrunAciklama", "Adet", "FaturaTarihi", "BirimFiyat", "MusteriID", "Ulke"]
eksik = [c for c in gerekli if c not in df.columns]
if eksik:
    raise ValueError(f"Eksik kolon(lar) bulundu: {eksik}. Excel kolon adlarını kontrol et.")
    
    
    

############################ 3) Tip dönüşümleri ############################

df["FaturaTarihi"] = pd.to_datetime(df["FaturaTarihi"], errors="coerce")
# MusteriID genellikle float gelir; temizlemeden sonra int'e çekmek daha mantıklı
df["MusteriID"] = pd.to_numeric(df["MusteriID"], errors="coerce")
df["Adet"] = pd.to_numeric(df["Adet"], errors="coerce")
df["BirimFiyat"] = pd.to_numeric(df["BirimFiyat"], errors="coerce")





############################ 4) Veri temizliği ############################

# 4.1) Eksik müşteri numaralarını çıkar (RFM müşteri bazlı olduğu için şart)
df = df.dropna(subset=["MusteriID"])
# 4.2) İptal/iade faturalarını çıkar (FaturaNo 'C' ile başlıyorsa)
# Not: Bazı kayıtlarda FaturaNo numeric gelebilir -> string'e çevirelim
df["FaturaNo"] = df["FaturaNo"].astype(str)
df = df[~df["FaturaNo"].str.startswith("C", na=False)]
# 4.3) Negatif veya sıfır adet/fiyatları çıkar
df = df[(df["Adet"] > 0) & (df["BirimFiyat"] > 0)]
# 4.4) Tarihi bozuk kayıtları çıkar
df = df.dropna(subset=["FaturaTarihi"])
# 4.5) Çok kritik: aynı fatura-ürün-müşteri tekrarları varsa kaldır (opsiyonel ama önerilir)
df = df.drop_duplicates(subset=["FaturaNo", "UrunKodu", "MusteriID"])




############################ 5) Türev değişken: ToplamTutar ############################
df["ToplamTutar"] = df["Adet"] * df["BirimFiyat"]
# MusteriID artık int yapılabilir
df["MusteriID"] = df["MusteriID"].astype(int)




############################ 6) Temel kontroller ############################
kontrol = {
    "ToplamKayit": len(df),
    "EksikMusteriID": int(df["MusteriID"].isna().sum()),
    "NegatifAdet": int((df["Adet"] <= 0).sum()),
    "NegatifFiyat": int((df["BirimFiyat"] <= 0).sum()),
    "MinTarih": df["FaturaTarihi"].min(),
    "MaxTarih": df["FaturaTarihi"].max(),
}
print("KONTROLLER:", kontrol)



############################ 7) SQL'e aktarım için CSV çıktı ############################
cikti_yolu = r"online_retail_temiz.csv"
df.to_csv(cikti_yolu, index=False, encoding="utf-8-sig")
print(f"Temiz veri CSV olarak kaydedildi: {cikti_yolu}")
