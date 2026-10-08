import Crypto
import Foundation

/// FastCDC 2020 content-defined chunking with the parameters a cache advertises for `SpliceBlob`: 128 KiB
/// minimum, 512 KiB average and 2 MiB maximum chunks at normalization level 2 and seed 0. Cut points match the
/// `fastcdc` crate's `v2020` chunker, so the chunks of a blob are the ones other clients of the cache publish.
enum REAPIChunking {
    static let minimumChunkBytes = 128 * 1024
    static let averageChunkBytes = 512 * 1024
    static let maximumChunkBytes = 2 * 1024 * 1024
    /// The most chunks a cache accepts in one blob's recipe.
    static let maximumChunks = 16384

    struct Chunk: Sendable, Equatable {
        let offset: Int64
        let digest: REAPI.Digest
    }

    /// Splits the file into chunks, failing when its content no longer matches `digest`. The cut function never
    /// looks further than the largest chunk, so the file is read through a window instead of loaded whole.
    static func chunks(of file: URL, digest: REAPI.Digest) throws -> [Chunk] {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var buffer: [UInt8] = []
        var start = 0
        var exhausted = false
        var offset: Int64 = 0
        var whole = SHA256()
        var chunks: [Chunk] = []
        // The tables are read once per byte, so the loop indexes them through pointers rather than the static arrays.
        let gear = UnsafeMutableBufferPointer<UInt64>.allocate(capacity: 256)
        let gearShifted = UnsafeMutableBufferPointer<UInt64>.allocate(capacity: 256)
        defer {
            gear.deallocate()
            gearShifted.deallocate()
        }
        _ = gear.initialize(from: Self.gear)
        _ = gearShifted.initialize(from: Self.gear.map { $0 << 1 })
        while true {
            while !exhausted, buffer.count - start < maximumChunkBytes {
                if start > 0 {
                    buffer.removeFirst(start)
                    start = 0
                }
                let data = try handle.read(upToCount: 2 * maximumChunkBytes) ?? Data()
                if data.isEmpty { exhausted = true } else { buffer.append(contentsOf: data) }
            }
            if start == buffer.count { break }
            let chunk = buffer.withUnsafeBufferPointer { pointer in
                let length = cut(UnsafeBufferPointer(rebasing: pointer[start...]), gear: gear, gearShifted: gearShifted)
                let bytes = UnsafeRawBufferPointer(UnsafeBufferPointer(rebasing: pointer[start ..< start + length]))
                whole.update(bufferPointer: bytes)
                return Chunk(offset: offset, digest: .with {
                    $0.hash = REAPI.hashString(SHA256.hash(data: bytes))
                    $0.sizeBytes = Int64(length)
                })
            }
            chunks.append(chunk)
            offset += chunk.digest.sizeBytes
            start += Int(chunk.digest.sizeBytes)
        }
        guard offset == digest.sizeBytes, REAPI.hashString(whole.finalize()) == digest.hash else {
            throw REAPICacheError.corruptBlob
        }
        return chunks
    }

    /// The length of the chunk that starts `source`, given the gear table and the table shifted left by one bit.
    static func cut(
        _ source: UnsafeBufferPointer<UInt8>,
        gear: UnsafeMutableBufferPointer<UInt64>,
        gearShifted: UnsafeMutableBufferPointer<UInt64>
    ) -> Int {
        let smallMask = Self.smallMask, smallMaskShifted = Self.smallMask << 1
        let largeMask = Self.largeMask, largeMaskShifted = Self.largeMask << 1
        var remaining = source.count
        if remaining <= minimumChunkBytes { return remaining }
        var center = averageChunkBytes
        if remaining > maximumChunkBytes {
            remaining = maximumChunkBytes
        } else if remaining < center {
            center = remaining
        }
        var index = minimumChunkBytes / 2
        var hash: UInt64 = 0
        while index < center / 2 {
            let position = index * 2
            hash = (hash << 2) &+ gearShifted[Int(source[position])]
            if hash & smallMaskShifted == 0 { return position }
            hash = hash &+ gear[Int(source[position + 1])]
            if hash & smallMask == 0 { return position + 1 }
            index += 1
        }
        while index < remaining / 2 {
            let position = index * 2
            hash = (hash << 2) &+ gearShifted[Int(source[position])]
            if hash & largeMaskShifted == 0 { return position }
            hash = hash &+ gear[Int(source[position + 1])]
            if hash & largeMask == 0 { return position + 1 }
            index += 1
        }
        return remaining
    }

    /// Masks for 2^(19 + 2) and 2^(19 - 2) bits: the average chunk size's bits, normalized at level 2.
    private static let smallMask: UInt64 = 0x0000_D917_6753_7000
    private static let largeMask: UInt64 = 0x0000_D907_0353_7000
    private static let gear: [UInt64] = [
        0x3B5D_3C7D_207E_37DC, 0x784D_68BA_9112_3086, 0xCD52_880F_882E_7298, 0xEACF_8E4E_19FD_CCA7,
        0xC31F_385D_FBD1_632B, 0x1D5F_2700_1E25_ABE6, 0x8313_0BDE_3C9A_D991, 0xC4B2_2567_6E9B_7649,
        0xAA32_9B29_E08E_B499, 0xB67F_CBD2_1E57_7D58, 0x0027_BAAA_DA2A_CF6B, 0xE3EF_2D5A_C73C_2226,
        0x0890_F24D_6ED3_12B7, 0xA809_E036_851D_7C7E, 0xF0A6_FE5E_0013_D81B, 0x1D02_6304_452C_EC14,
        0x0386_4632_648E_248F, 0xCDAA_CF3D_CD92_B9B4, 0xF5E0_12E6_3C18_7856, 0x8862_F9D3_821C_00B6,
        0xA82F_7338_750F_6F8A, 0x1E58_3DC6_C1CB_0B6F, 0x7A31_45B6_9743_A7F1, 0xABB2_0FEE_4048_07EB,
        0xB14B_3CFE_07B8_3A5D, 0xB9DC_2789_8ADB_9A0F, 0x3703_F5E9_1BAA_62BE, 0xCF0B_B866_815F_7D98,
        0x3D98_67C4_1EA9_DCD3, 0x1BE1_FA65_442B_F22C, 0x1430_0DA4_C556_31D9, 0xE698_E9CB_C654_5C99,
        0x4763_107E_C64E_92A5, 0xC658_21FC_6569_6A24, 0x7619_6C06_4822_F0B7, 0x485B_E841_F352_5E01,
        0xF652_BC9C_8597_4FF5, 0xCAD8_352F_ACE9_E3E9, 0x2A6E_D1DC_EB35_E98E, 0xC6F4_83BA_DC11_680F,
        0x3CFD_8C17_E9CF_12F1, 0x89B8_3C5E_2EA5_6471, 0xAE66_5CFD_24E3_92A9, 0xEC33_C4E5_04CB_8915,
        0x3FB9_B15F_C9FE_7451, 0xD7FD_1FD1_945F_2195, 0x31AD_E085_3443_EFD8, 0x255E_FC98_63E1_E2D2,
        0x10EA_B600_8D56_42CF, 0x46F0_4863_257A_C804, 0xA52D_C42A_789A_27D3, 0xDAAA_DF9C_E77A_F565,
        0x6B47_9CD5_3D87_FEBB, 0x6309_E2D3_F93D_B72F, 0xC573_8FFB_AA1F_F9D6, 0x6BD5_7F3F_25AF_7968,
        0x6760_5486_D90D_0A4A, 0xE14D_0B96_63BF_BDAE, 0xB7BB_D8D8_16EB_0414, 0xDEF8_A4F1_6B35_A116,
        0xE793_2D85_AAAF_FED6, 0x0816_1CBA_E90C_FD48, 0x8555_07BE_B294_F08B, 0x9123_4EA6_FFD3_99B2,
        0xAD70_CF4B_2435_F302, 0xD289_A975_65BC_2D27, 0x8E55_8437_FFCA_99DE, 0x96D2_704B_7115_C040,
        0x0889_BBCD_FC66_0E41, 0x5E0D_4E67_DC92_128D, 0x72A9_F891_7063_ED97, 0x438B_69D4_09E0_16E3,
        0xDF4F_ED8A_5D8A_4397, 0x00F4_1DCF_41D4_03F7, 0x4814_EB03_8E52_603F, 0x9DAF_BACC_58E2_D651,
        0xFE2F_458E_4BE1_70AF, 0x4457_EC41_4DF6_A940, 0x06E6_2F14_5112_3314, 0xBD10_14D1_73BA_92CC,
        0xDEF3_18E2_5ED5_7760, 0x9FEA_0DE9_DFCA_8525, 0x459D_E1E7_6C20_624B, 0xAEEC_1896_17E2_D666,
        0x126A_2C06_AB5A_83CB, 0xB132_1532_360F_6132, 0x6542_1503_DBB4_0123, 0x2D67_C287_EA08_9AB3,
        0x6C93_BFF5_A56B_D6B6, 0x4FFB_2036_CAB6_D98D, 0xCE7B_785B_1BE7_AD4F, 0xEDB4_2EF6_189F_D163,
        0xDC90_5288_7039_88F6, 0x365F_9C1D_2C69_1884, 0xC640_5836_80D9_9BFE, 0x3CD4_624C_0759_3EC6,
        0x7F1E_A8D8_5D7C_5805, 0x0148_42D4_80B5_7149, 0x0B64_9BCB_5A82_8688, 0xBCD5_708E_D79B_18F0,
        0xE987_C862_FBD2_F2F0, 0x9827_3167_1F0C_D82C, 0xBAF1_3E8B_16D8_C063, 0x8EA3_109C_BD95_1BBA,
        0xD141_045B_FB38_5CAD, 0x2ACB_C1A0_AF1F_7D30, 0xE644_4D89_DF03_BFDF, 0xA18C_C771_B818_8FF9,
        0x9834_429D_B01C_39BB, 0x214A_DD07_FE08_6A1F, 0x8F07_C19B_1F6B_3FF9, 0x56A2_97B1_BF4F_FE55,
        0x94D5_58E4_93C5_4FC7, 0x40BF_C24C_7645_52CB, 0x931A_706F_8A85_20CB, 0x3222_9D32_2935_BD52,
        0x2560_D0F5_DC4F_EFAF, 0x9DBC_C483_5596_9BB6, 0x0FD8_1C39_85C0_B56A, 0xE038_17E1_560F_2BDA,
        0xC1BB_4F81_D892_B2D5, 0xB0C4_864F_4E28_D2D7, 0x3ECC_49F9_D9D6_C263, 0x5130_7E99_B52B_A65E,
        0x8AF2_B688_DA84_A752, 0xF5D7_2523_B91B_20B6, 0x6D95_FF1F_F463_4806, 0x562F_2155_5458_339A,
        0xC0CE_47F8_8933_6346, 0x4878_23E5_089B_40D8, 0xE472_7C7E_BC6D_9592, 0x5A8F_7277_E949_70BA,
        0xFCA2_F406_B1C8_BB50, 0x5B1F_8A95_F179_1070, 0xD304_AF9F_C902_8605, 0x5440_AB7F_C930_E748,
        0x312D_25FB_CA2A_B5A1, 0x10F4_A4B2_34A4_D575, 0x9030_1D55_047E_7473, 0x3B63_7288_6C61_591E,
        0x2934_02B7_7C44_4E06, 0x451F_34A4_D3E9_7DD7, 0x3158_D814_D81B_C57B, 0x0349_4242_5B9B_DA69,
        0xE203_2FF9_E532_D9BB, 0x62AE_066B_8B21_79E5, 0x9545_E10C_2F8D_71D8, 0x7FF7_483E_B2D2_3FC0,
        0x0094_5FCE_BDC9_8D86, 0x8764_BBBE_99B2_6CA2, 0x1B1E_C622_84C0_BFC3, 0x58E0_FCC4_F0AA_362B,
        0x5F4A_BEFA_878D_458D, 0xFD74_AC2F_9607_C519, 0xA4E3_FB37_DF8C_BFA9, 0xBF69_7E43_CAC5_74E5,
        0x86F1_4A3F_68F4_CD53, 0x24A2_3D07_6F1C_E522, 0xE725_CD80_4886_8CC8, 0xBF3C_729E_B246_4362,
        0xD8F6_CD57_B3CC_1ED8, 0x6329_E524_2554_1577, 0x62AA_688A_D5AE_1AC0, 0x0A24_2566_269B_F845,
        0x168B_1A47_53AC_A74B, 0xF789_AFEF_FF2E_7E3C, 0x6C33_6209_3B6F_CCDB, 0x4CE8_F50B_D28C_09B2,
        0x006A_2DB9_5AE8_AA93, 0x975B_0D62_3C3D_1A8C, 0x1860_5D39_3533_8C5B, 0x5BB6_F613_6CAD_3C71,
        0x0F53_A207_01F8_D8A6, 0xAB8C_5AD2_E7E9_3C67, 0x40B5_AC51_27AC_AA29, 0x8C7B_F63C_2075_895F,
        0x78BD_9F7E_014A_805C, 0xB2C9_E9F4_F9C8_C032, 0xEFD6_0498_27EB_91F3, 0x2BE4_59F4_82C1_6FBD,
        0xD92C_E0C5_745A_AA8C, 0x0AAA_8FB2_98D9_65B9, 0x2B37_F92C_6C80_3B15, 0x8C54_A5E9_4E0F_0E78,
        0x95F9_B6E9_0C0A_3032, 0xE793_9FAA_436C_7874, 0xD16B_FE8F_6A8A_40C9, 0x4498_2B86_263F_D2FA,
        0xE285_FB39_F984_E583, 0x779A_8DF7_2D76_19D3, 0xF2D7_9A8D_E8D5_DD1E, 0xD103_7354_D666_84E2,
        0x004C_82A4_E668_A8E5, 0x31D4_0A76_68B0_44E6, 0xD705_7853_8BD0_2C11, 0xDB45_4310_78C5_F482,
        0x9771_21BB_7F6A_51AD, 0x73D5_CCBD_34EF_F8DD, 0xE437_A07D_356E_17CD, 0x47B2_7820_43C9_5627,
        0x9FB2_5141_3E41_D49A, 0xCCD7_0B60_6525_13D3, 0x1C95_B31E_8A1B_49B2, 0xCAE7_3DFD_1BCB_4C1B,
        0x34D9_8331_B1F5_B70F, 0x784E_39F2_2338_D92F, 0x1861_3D4A_064D_F420, 0xF1D8_DAE2_5F0B_CEBE,
        0x33F7_7C15_AE85_5EFC, 0x3C88_B3B9_12EB_109C, 0x956A_2EC9_6BAF_EEA5, 0x1AA0_05B5_E0AD_0E87,
        0x5500_D705_27C4_BB8E, 0xE36C_5719_6421_CC44, 0x13C4_D286_CC36_EE39, 0x5654_A23D_818B_2A81,
        0x77B1_DC13_D161_ABDC, 0x734F_44DE_5F8D_5EB5, 0x6071_7E17_4A6C_89A2, 0xD47D_9649_266A_211E,
        0x5B13_A432_2BB6_9E90, 0xF766_9609_F8B5_FC3C, 0x21E6_AC55_BEDC_DAC9, 0x9B56_B62B_6116_6DEA,
        0xF48F_66B9_3979_7E9C, 0x35F3_32F9_C0E6_AE9A, 0xCC73_3F6A_9A87_8DB0, 0x3DA1_61E4_1CC1_08C2,
        0xB7D7_4AE5_3591_4D51, 0x4D49_3B0B_11D3_6469, 0xCE26_4D1D_FBA9_741A, 0xA9D1_F2DC_7436_DC06,
        0x7073_8016_604C_2A27, 0x231D_36E9_6E93_F3D5, 0x7666_8811_9783_8D19, 0x4A2A_8309_0AAA_D40C,
        0xF1E7_6159_1668_B35D, 0x7363_2364_97F7_30A7, 0x3010_80E3_7379_DD4D, 0x502D_EA29_7182_7042,
        0xC2C5_EB85_8F32_625F, 0x786A_FB9E_DFAF_BDFF, 0xDAEE_0D86_8490_B2A4, 0x6173_66B3_2686_09F6,
        0xAE0E_35A0_FE46_173E, 0xD1A0_7DE9_3E82_4F11, 0x079B_8B11_5EA4_CCA8, 0x93A9_9274_558F_AEBB,
        0xFB1E_6E22_E08A_03B3, 0xEA63_5FDB_A369_8DD0, 0xCF53_6593_2850_3A5C, 0xCDE3_B31E_6FD5_D780,
        0x8E3E_4221_D361_4413, 0xEF14_D0D8_6BF1_A22C, 0xE1D8_30D3_F16C_5DDB, 0xAABD_2B2A_4515_04E1,
    ]
}
