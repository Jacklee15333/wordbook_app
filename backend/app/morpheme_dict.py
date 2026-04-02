"""
★ v5.2: 专业词根词缀数据库与构词法分解引擎
========================================================
数据来源:
  - 基于 Merriam-Webster's Vocabulary Builder 词根体系
  - 参考 Oxford English Etymology / Chambers Dictionary of Etymology
  - 覆盖拉丁语、希腊语核心构词语素 500+
  - 适用于高中 / CET-4 / CET-6 / 考研 / GRE 核心词汇

分解算法:
  - 贪心最长匹配 + 动态规划回溯
  - 支持前缀同化变体 (ad→ac/af/ag/al 等)
  - 支持词根拼写变体 (cap/cep/ceiv/ceit 等)
  - 质量评分过滤，仅保留高置信度分解结果
========================================================
"""

from typing import Optional

# ══════════════════════════════════════════════════════════════
# 前缀数据库  { 前缀: (含义_中文, 含义_英文, 原始形式) }
# ══════════════════════════════════════════════════════════════

PREFIXES: dict[str, tuple[str, str, str]] = {
    # ── a- / ab- / abs- : 离开 ──
    "ab":    ("离开,从", "away from", "ab-"),
    "abs":   ("离开,从", "away from", "abs-"),

    # ── ad- 及其同化变体 : 向,朝 ──
    "ad":    ("向,朝", "to, toward", "ad-"),
    "ac":    ("向,朝", "to, toward", "ad-"),
    "af":    ("向,朝", "to, toward", "ad-"),
    "ag":    ("向,朝", "to, toward", "ad-"),
    "al":    ("向,朝", "to, toward", "ad-"),
    "an":    ("向,朝", "to, toward", "ad-"),
    "ap":    ("向,朝", "to, toward", "ad-"),
    "ar":    ("向,朝", "to, toward", "ad-"),
    "as":    ("向,朝", "to, toward", "ad-"),
    "at":    ("向,朝", "to, toward", "ad-"),

    # ── ante- : 前 ──
    "ante":  ("前,先", "before", "ante-"),
    "anti":  ("反,对抗", "against", "anti-"),

    # ── auto- : 自己 ──
    "auto":  ("自己", "self", "auto-"),

    # ── bene- / ben- : 好 ──
    "bene":  ("好,善", "good, well", "bene-"),
    "ben":   ("好,善", "good, well", "bene-"),

    # ── bi- : 二 ──
    "bi":    ("二,双", "two", "bi-"),

    # ── circum- : 环绕 ──
    "circum":("环绕", "around", "circum-"),

    # ── co- / com- / con- / col- / cor- : 共同 ──
    "com":   ("共同,一起", "together, with", "com-"),
    "con":   ("共同,一起", "together, with", "com-"),
    "col":   ("共同,一起", "together, with", "com-"),
    "cor":   ("共同,一起", "together, with", "com-"),
    "co":    ("共同,一起", "together, with", "com-"),

    # ── contra- / counter- : 反对 ──
    "contra":("相反,对抗", "against", "contra-"),
    "counter":("相反,对抗", "against", "counter-"),

    # ── de- : 向下,去除 ──
    "de":    ("向下,去除", "down, away", "de-"),

    # ── dis- / di- / dif- : 分开,否定 ──
    "dis":   ("分开,否定", "apart, not", "dis-"),
    "dif":   ("分开,否定", "apart, not", "dis-"),
    "di":    ("分开,否定", "apart, not", "dis-"),

    # ── e- / ex- / ef- : 出 ──
    "ex":    ("出,外", "out of", "ex-"),
    "ef":    ("出,外", "out of", "ex-"),
    "e":     ("出,外", "out of", "ex-"),

    # ── en- / em- : 使成为 ──
    "en":    ("使成为", "make, put in", "en-"),
    "em":    ("使成为", "make, put in", "en-"),

    # ── extra- : 超出 ──
    "extra": ("超出,外", "beyond", "extra-"),

    # ── fore- : 前 ──
    "fore":  ("前,预先", "before", "fore-"),

    # ── hyper- : 超过 ──
    "hyper": ("超过,过度", "over, excessive", "hyper-"),

    # ── in- / im- / il- / ir- : 不/向内 ──
    "in":    ("不;向内", "not; into", "in-"),
    "im":    ("不;向内", "not; into", "in-"),
    "il":    ("不", "not", "in-"),
    "ir":    ("不", "not", "in-"),

    # ── inter- : 之间 ──
    "inter": ("之间,互相", "between", "inter-"),

    # ── intra- / intro- : 向内 ──
    "intra": ("在内部", "within", "intra-"),
    "intro": ("向内", "inward", "intro-"),

    # ── mal- : 坏 ──
    "mal":   ("坏,恶", "bad", "mal-"),

    # ── micro- : 微小 ──
    "micro": ("微小", "small", "micro-"),

    # ── mis- : 错误 ──
    "mis":   ("错误,不当", "wrong, bad", "mis-"),

    # ── mono- / mon- : 单一 ──
    "mono":  ("单一", "one, single", "mono-"),
    "mon":   ("单一", "one, single", "mono-"),

    # ── multi- : 多 ──
    "multi": ("多", "many", "multi-"),

    # ── non- : 非 ──
    "non":   ("非,不", "not", "non-"),

    # ── ob- / oc- / of- / op- : 逆,向 ──
    "ob":    ("逆,向", "against, toward", "ob-"),
    "oc":    ("逆,向", "against, toward", "ob-"),
    "of":    ("逆,向", "against, toward", "ob-"),
    "op":    ("逆,向", "against, toward", "ob-"),

    # ── out- : 超过 ──
    "out":   ("超过,外", "beyond, out", "out-"),

    # ── over- : 过度 ──
    "over":  ("过度,在上", "over, excessive", "over-"),

    # ── per- : 完全,贯穿 ──
    "per":   ("完全,贯穿", "through, thoroughly", "per-"),

    # ── poly- : 多 ──
    "poly":  ("多", "many", "poly-"),

    # ── post- : 后 ──
    "post":  ("后,之后", "after", "post-"),

    # ── pre- : 前 ──
    "pre":   ("前,预先", "before", "pre-"),

    # ── pro- : 向前 ──
    "pro":   ("向前,赞成", "forward, for", "pro-"),

    # ── re- : 再,回 ──
    "re":    ("再,回", "again, back", "re-"),

    # ── retro- : 向后 ──
    "retro": ("向后,回", "backward", "retro-"),

    # ── se- : 分离 ──
    "se":    ("分离", "apart", "se-"),

    # ── semi- : 半 ──
    "semi":  ("半", "half", "semi-"),

    # ── sub- / suc- / suf- / sug- / sup- / sur- / sus- : 下 ──
    "sub":   ("下,次", "under, below", "sub-"),
    "suc":   ("下,次", "under, below", "sub-"),
    "suf":   ("下,次", "under, below", "sub-"),
    "sug":   ("下,次", "under, below", "sub-"),
    "sup":   ("下,次", "under, below", "sub-"),
    "sur":   ("在上", "over, above", "sur-"),
    "sus":   ("下,次", "under, below", "sub-"),

    # ── super- / supra- : 超级 ──
    "super": ("超级,在上", "above, beyond", "super-"),
    "supra": ("超越", "above", "supra-"),

    # ── sym- / syn- : 共同 ──
    "sym":   ("共同", "together", "syn-"),
    "syn":   ("共同", "together", "syn-"),

    # ── tele- : 远 ──
    "tele":  ("远", "far, distant", "tele-"),

    # ── trans- / tra- : 穿越 ──
    "trans": ("穿越,转", "across", "trans-"),
    "tra":   ("穿越,转", "across", "trans-"),

    # ── tri- : 三 ──
    "tri":   ("三", "three", "tri-"),

    # ── ultra- : 超 ──
    "ultra": ("超,极", "beyond", "ultra-"),

    # ── un- : 不,反 ──
    "un":    ("不,反", "not, reverse", "un-"),

    # ── under- : 不足 ──
    "under": ("不足,在下", "below, less", "under-"),

    # ── uni- : 单一 ──
    "uni":   ("单一", "one", "uni-"),

    # ── with- : 反对 ──
    "with":  ("反对,向后", "against, back", "with-"),
}

# ══════════════════════════════════════════════════════════════
# 词根数据库  { 词根: (含义_中文, 含义_英文, 词源) }
# 包含常见拼写变体
# ══════════════════════════════════════════════════════════════

ROOTS: dict[str, tuple[str, str, str]] = {
    # ── act / ag : 做,驱动 ──
    "act":    ("做,行动", "do, drive", "L. agere"),
    "ag":     ("做,驱动", "do, drive", "L. agere"),
    "ig":     ("做,驱动", "do, drive", "L. agere"),

    # ── am / amor : 爱 ──
    "am":     ("爱", "love", "L. amare"),
    "amor":   ("爱", "love", "L. amare"),

    # ── anim : 生命,精神 ──
    "anim":   ("生命,精神", "life, spirit", "L. anima"),

    # ── ann / enn : 年 ──
    "ann":    ("年", "year", "L. annus"),
    "enn":    ("年", "year", "L. annus"),

    # ── aud / audi : 听 ──
    "aud":    ("听", "hear", "L. audire"),
    "audi":   ("听", "hear", "L. audire"),

    # ── bell : 战争 ──
    "bell":   ("战争", "war", "L. bellum"),

    # ── bio : 生命 ──
    "bio":    ("生命", "life", "Gk. bios"),

    # ── brev : 短 ──
    "brev":   ("短", "short", "L. brevis"),

    # ── cad / cas / cid : 落下 ──
    "cad":    ("落下", "fall", "L. cadere"),
    "cas":    ("落下", "fall", "L. cadere"),
    "cid":    ("落下,发生", "fall, happen", "L. cadere"),

    # ── cap / cep / ceiv / ceit / cip / cup : 拿,取 ──
    "cap":    ("拿,取", "take, seize", "L. capere"),
    "cep":    ("拿,取", "take, seize", "L. capere"),
    "ceiv":   ("拿,取", "take, seize", "L. capere"),
    "ceit":   ("拿,取", "take, seize", "L. capere"),
    "cip":    ("拿,取", "take, seize", "L. capere"),
    "cup":    ("拿,取", "take, seize", "L. capere"),
    "capt":   ("拿,取", "take, seize", "L. capere"),
    "cept":   ("拿,取", "take, seize", "L. capere"),

    # ── ced / cess / ceed / cede : 走,让步 ──
    "ced":    ("走,让步", "go, yield", "L. cedere"),
    "ceed":   ("走,让步", "go, yield", "L. cedere"),
    "cede":   ("走,让步", "go, yield", "L. cedere"),
    "cess":   ("走,让步", "go, yield", "L. cedere"),

    # ── cent / centi : 百 ──
    "cent":   ("百", "hundred", "L. centum"),
    "centi":  ("百", "hundred", "L. centum"),

    # ── cern / cert / cret : 分辨,确定 ──
    "cern":   ("分辨", "separate, decide", "L. cernere"),
    "cert":   ("确定", "sure, decide", "L. cernere"),
    "cret":   ("分辨", "separate", "L. cernere"),

    # ── chron : 时间 ──
    "chron":  ("时间", "time", "Gk. chronos"),

    # ── cit : 引发,召唤 ──
    "cit":    ("引发,召唤", "call, arouse", "L. citare"),

    # ── civ / cit : 公民 ──
    "civ":    ("公民", "citizen", "L. civis"),

    # ── claim / clam : 喊,叫 ──
    "claim":  ("喊,叫", "cry out", "L. clamare"),
    "clam":   ("喊,叫", "cry out", "L. clamare"),

    # ── clar : 清楚 ──
    "clar":   ("清楚", "clear", "L. clarus"),

    # ── clin / cliv : 倾斜 ──
    "clin":   ("倾斜", "lean, bend", "L. clinare"),

    # ── clos / clud / clus : 关闭 ──
    "clos":   ("关闭", "close, shut", "L. claudere"),
    "clud":   ("关闭", "close, shut", "L. claudere"),
    "clus":   ("关闭", "close, shut", "L. claudere"),

    # ── cogn / gnos / gni / gnit / know : 知道 ──
    "cogn":   ("知道,认识", "know", "L. cognoscere"),
    "gnos":   ("知道", "know", "Gk. gnosis"),
    "gni":    ("知道,认识", "know", "L. cognoscere"),
    "gnit":   ("知道,认识", "know", "L. cognoscere"),

    # ── cord / cour / card : 心 ──
    "cord":   ("心", "heart", "L. cor"),
    "cour":   ("心,勇气", "heart", "L. cor"),
    "card":   ("心", "heart", "Gk. kardia"),

    # ── corp / corpor : 身体 ──
    "corp":   ("身体", "body", "L. corpus"),
    "corpor": ("身体", "body", "L. corpus"),

    # ── cosm : 宇宙 ──
    "cosm":   ("宇宙,秩序", "universe, order", "Gk. kosmos"),

    # ── cre / cresc / cret : 生长 ──
    "cre":    ("生长,创造", "grow, create", "L. crescere"),
    "cresc":  ("生长", "grow", "L. crescere"),
    "creat":  ("创造", "create", "L. creare"),

    # ── cred : 相信 ──
    "cred":   ("相信", "believe", "L. credere"),

    # ── cur / curs / cour / cours : 跑 ──
    "cur":    ("跑,关心", "run, care", "L. currere"),
    "curs":   ("跑", "run", "L. currere"),
    "cour":   ("跑", "run", "L. currere"),
    "cours":  ("跑", "run", "L. currere"),

    # ── cur : 关心 ──
    "cure":   ("关心", "care", "L. cura"),

    # ── dem / demo : 人民 ──
    "dem":    ("人民", "people", "Gk. demos"),
    "demo":   ("人民", "people", "Gk. demos"),

    # ── dic / dict : 说 ──
    "dic":    ("说", "say, speak", "L. dicere"),
    "dict":   ("说", "say, speak", "L. dicere"),
    "dit":    ("说", "say, speak", "L. dicere"),

    # ── doc / doct : 教 ──
    "doc":    ("教", "teach", "L. docere"),
    "doct":   ("教", "teach", "L. docere"),

    # ── dom / domin : 统治,家 ──
    "domin":  ("统治", "master, rule", "L. dominus"),

    # ── don / dat / dit : 给 ──
    "don":    ("给", "give", "L. donare"),
    "dat":    ("给", "give", "L. dare"),
    "dit":    ("给", "give", "L. dare"),

    # ── du / duo / dub : 二 ──
    "du":     ("二", "two", "L. duo"),
    "duo":    ("二", "two", "L. duo"),
    "dub":    ("二,疑", "two, doubt", "L. dubius"),

    # ── duc / duct : 引导 ──
    "duc":    ("引导", "lead", "L. ducere"),
    "duct":   ("引导", "lead", "L. ducere"),

    # ── dur : 持久 ──
    "dur":    ("持久,硬", "hard, lasting", "L. durus"),

    # ── equ : 相等 ──
    "equ":    ("相等", "equal", "L. aequus"),

    # ── err : 错误,漫游 ──
    "err":    ("错误,漫游", "wander, err", "L. errare"),

    # ── fac / fic / fect / fact / feit / fit : 做,制造 ──
    "fac":    ("做,制造", "make, do", "L. facere"),
    "fic":    ("做,制造", "make, do", "L. facere"),
    "fect":   ("做,制造", "make, do", "L. facere"),
    "fact":   ("做,制造", "make, do", "L. facere"),
    "feit":   ("做,制造", "make, do", "L. facere"),
    "fit":    ("做,制造", "make, do", "L. facere"),
    "fy":     ("做,使成为", "make", "L. facere"),
    "fic":    ("做,制造", "make, do", "L. facere"),

    # ── fall / fals : 欺骗 ──
    "fall":   ("欺骗,错", "deceive", "L. fallere"),
    "fals":   ("欺骗,假", "false", "L. falsus"),
    "fault":  ("错误", "fault", "L. fallere"),

    # ── fer : 带,承载 ──
    "fer":    ("带,承载", "carry, bear", "L. ferre"),

    # ── fess : 坦白,声明 ──
    "fess":   ("坦白,声明", "speak, confess", "L. fateri"),

    # ── fid / fi : 信任 ──
    "fid":    ("信任", "trust, faith", "L. fides"),
    "fi":     ("信任", "trust, faith", "L. fides"),

    # ── fin : 结束,范围 ──
    "fin":    ("结束,范围", "end, limit", "L. finis"),

    # ── firm : 坚固 ──
    "firm":   ("坚固", "firm, strong", "L. firmus"),

    # ── fix : 固定 ──
    "fix":    ("固定", "fix, fasten", "L. fixus"),

    # ── flam / flagr : 燃烧 ──
    "flam":   ("燃烧", "burn, flame", "L. flamma"),
    "flagr":  ("燃烧", "burn", "L. flagrare"),

    # ── flect / flex : 弯曲 ──
    "flect":  ("弯曲", "bend", "L. flectere"),
    "flex":   ("弯曲", "bend", "L. flectere"),

    # ── flu / flux / fluct : 流 ──
    "flu":    ("流", "flow", "L. fluere"),
    "flux":   ("流", "flow", "L. fluere"),
    "fluct":  ("流,波动", "flow, wave", "L. fluere"),

    # ── form : 形状 ──
    "form":   ("形状,形成", "shape, form", "L. forma"),

    # ── fort / forc : 强 ──
    "fort":   ("强", "strong", "L. fortis"),
    "forc":   ("强", "strong", "L. fortis"),

    # ── found / fund / fus : 底,倒 ──
    "found":  ("底,建立", "base, found", "L. fundare"),
    "fund":   ("底,基础", "base, bottom", "L. fundus"),
    "fus":    ("倒,融合", "pour, melt", "L. fundere"),

    # ── frag / fract / fring : 碎 ──
    "frag":   ("碎", "break", "L. frangere"),
    "fract":  ("碎", "break", "L. frangere"),
    "fring":  ("碎", "break", "L. frangere"),

    # ── gen / gon / gn : 产生,种类 ──
    "gen":    ("产生,种类", "birth, produce", "Gk. genos"),
    "gon":    ("角", "angle", "Gk. gonia"),
    "gn":     ("产生", "produce", "L. gignere"),

    # ── gest / ger : 搬运,带来 ──
    "gest":   ("搬运,带来", "carry, bring", "L. gerere"),
    "ger":    ("搬运,带来", "carry, bring", "L. gerere"),

    # ── geo : 地球 ──
    "geo":    ("地球,地", "earth", "Gk. ge"),

    # ── grad / gress / gred : 步,走 ──
    "grad":   ("步,等级", "step, grade", "L. gradi"),
    "gress":  ("步,走", "step, walk", "L. gradi"),
    "gred":   ("步,走", "step, walk", "L. gradi"),

    # ── graph / gram : 写,画 ──
    "graph":  ("写,画", "write", "Gk. graphein"),
    "gram":   ("写,字", "write, letter", "Gk. gramma"),

    # ── grat : 感激,愉快 ──
    "grat":   ("感激,愉快", "pleasing, thankful", "L. gratus"),

    # ── grav / griev : 重 ──
    "grav":   ("重", "heavy", "L. gravis"),
    "griev":  ("重,悲痛", "heavy, grieve", "L. gravis"),

    # ── hab / hib / habit : 拥有,居住 ──
    "hab":    ("拥有,居住", "have, hold", "L. habere"),
    "hib":    ("拥有,持有", "have, hold", "L. habere"),
    "habit":  ("拥有,居住", "have, dwell", "L. habere"),

    # ── her / hes : 粘附 ──
    "her":    ("粘附", "stick", "L. haerere"),
    "hes":    ("粘附", "stick", "L. haerere"),

    # ── hum : 人,地 ──
    "hum":    ("人,地", "human, ground", "L. humus"),
    "human":  ("人", "human", "L. humanus"),

    # ── hydr : 水 ──
    "hydr":   ("水", "water", "Gk. hydor"),

    # ── ject / jac : 投掷 ──
    "ject":   ("投掷", "throw", "L. jacere"),
    "jac":    ("投掷", "throw", "L. jacere"),

    # ── join / junct / jug : 连接 ──
    "join":   ("连接", "join", "L. jungere"),
    "junct":  ("连接", "join", "L. jungere"),
    "jug":    ("连接", "join, yoke", "L. jugum"),

    # ── jud / jur / jus / just : 法律,判断 ──
    "jud":    ("判断", "judge", "L. judicare"),
    "jur":    ("法律,发誓", "law, swear", "L. jus"),
    "jus":    ("法律,公正", "law, right", "L. jus"),
    "just":   ("公正", "just, right", "L. justus"),

    # ── labor : 劳动 ──
    "labor":  ("劳动", "work", "L. labor"),

    # ── lat : 带来,放 ──
    "lat":    ("带来,放", "carry, bear", "L. latus"),

    # ── leg / lig / lect : 选,读,法律 ──
    "leg":    ("法律,读,选", "law, read, choose", "L. legere"),
    "lig":    ("选,绑", "choose, bind", "L. ligare"),
    "lect":   ("选,读", "choose, read", "L. legere"),

    # ── lev : 轻,举 ──
    "lev":    ("轻,举", "light, raise", "L. levis"),

    # ── liber : 自由 ──
    "liber":  ("自由", "free", "L. liber"),
    "liver":  ("自由,释放", "free, deliver", "L. liberare"),

    # ── lingu / langu : 语言 ──
    "lingu":  ("语言", "language, tongue", "L. lingua"),
    "langu":  ("语言", "language", "L. lingua"),

    # ── lit / liter : 文字 ──
    "lit":    ("文字", "letter", "L. littera"),
    "liter":  ("文字", "letter", "L. littera"),

    # ── loc : 地方 ──
    "loc":    ("地方", "place", "L. locus"),

    # ── log / logue / loqu / locu : 说,学 ──
    "log":    ("说,学", "word, study", "Gk. logos"),
    "logue":  ("说,学", "word, study", "Gk. logos"),
    "loqu":   ("说", "speak", "L. loqui"),
    "locu":   ("说", "speak", "L. loqui"),

    # ── luc / lum / lust / lumin : 光 ──
    "luc":    ("光", "light", "L. lux"),
    "lum":    ("光", "light", "L. lumen"),
    "lust":   ("光", "light", "L. lustrare"),
    "lumin":  ("光", "light", "L. lumen"),

    # ── man / manu : 手 ──
    "man":    ("手", "hand", "L. manus"),
    "manu":   ("手", "hand", "L. manus"),
    "mani":   ("手", "hand", "L. manus"),

    # ── mand / mend : 命令,委托 ──
    "mand":   ("命令", "order, entrust", "L. mandare"),
    "mend":   ("命令", "order", "L. mandare"),

    # ── marin / mar / mer : 海 ──
    "marin":  ("海", "sea", "L. mare"),
    "mar":    ("海", "sea", "L. mare"),

    # ── med / medi : 中间 ──
    "med":    ("中间", "middle", "L. medius"),
    "medi":   ("中间", "middle", "L. medius"),

    # ── mem / memor : 记忆 ──
    "mem":    ("记忆", "remember", "L. memor"),
    "memor":  ("记忆", "remember", "L. memor"),

    # ── ment : 心智 ──
    "ment":   ("心智", "mind", "L. mens"),

    # ── merc / merch : 贸易 ──
    "merc":   ("贸易", "trade", "L. merx"),
    "merch":  ("贸易", "trade", "L. merx"),

    # ── merg / mers : 沉没 ──
    "merg":   ("沉没", "dip, plunge", "L. mergere"),
    "mers":   ("沉没", "dip, plunge", "L. mergere"),

    # ── migr : 迁移 ──
    "migr":   ("迁移", "move, migrate", "L. migrare"),

    # ── min : 小,突出 ──
    "min":    ("小,突出", "small, project", "L. minor"),
    "mini":   ("小", "small", "L. minimus"),

    # ── mir : 惊奇,看 ──
    "mir":    ("惊奇,看", "wonder, look", "L. mirari"),

    # ── miss / mit / mis : 送,发 ──
    "miss":   ("送,发", "send", "L. mittere"),
    "mit":    ("送,发", "send", "L. mittere"),
    "mis":    ("送,发", "send", "L. mittere"),

    # ── mob / mot / mov : 移动 ──
    "mob":    ("移动", "move", "L. movere"),
    "mot":    ("移动", "move", "L. movere"),
    "mov":    ("移动", "move", "L. movere"),

    # ── mod : 方式,适度 ──
    "mod":    ("方式,适度", "manner, measure", "L. modus"),

    # ── mon / monit : 警告,提醒 ──
    "monit":  ("警告", "warn, advise", "L. monere"),

    # ── mor / mort : 死 ──
    "mor":    ("死,习俗", "death, custom", "L. mors"),
    "mort":   ("死", "death", "L. mors"),

    # ── morph : 形态 ──
    "morph":  ("形态", "form, shape", "Gk. morphe"),

    # ── nat / nasc / nai : 出生 ──
    "nat":    ("出生", "born", "L. nasci"),
    "nasc":   ("出生", "born", "L. nasci"),
    "nai":    ("出生", "born", "L. nasci"),

    # ── nav / nau : 船 ──
    "nav":    ("船", "ship", "L. navis"),
    "nau":    ("船", "ship", "Gk. naus"),

    # ── nect / nex : 连结 ──
    "nect":   ("连结,绑", "bind, connect", "L. nectere"),
    "nex":    ("连结", "bind", "L. nectere"),

    # ── neg : 否定 ──
    "neg":    ("否定", "deny, negate", "L. negare"),

    # ── nom / nym / nomin : 名字 ──
    "nom":    ("名字", "name", "Gk. onoma"),
    "nym":    ("名字", "name", "Gk. onoma"),
    "nomin":  ("名字", "name", "L. nomen"),

    # ── norm : 规范 ──
    "norm":   ("规范", "rule, standard", "L. norma"),

    # ── not / nosc : 知道,标记 ──
    "not":    ("知道,标记", "know, mark", "L. notare"),
    "nosc":   ("知道", "know", "L. noscere"),

    # ── nov / new : 新 ──
    "nov":    ("新", "new", "L. novus"),

    # ── numer : 数 ──
    "numer":  ("数", "number", "L. numerus"),

    # ── ord / ordin : 顺序 ──
    "ord":    ("顺序", "order", "L. ordo"),
    "ordin":  ("顺序", "order", "L. ordo"),

    # ── pand / pans / pass : 展开,通过 ──
    "pand":   ("展开", "spread", "L. pandere"),
    "pans":   ("展开", "spread", "L. pandere"),
    "pass":   ("通过,忍受", "pass, suffer", "L. passus"),

    # ── par / part : 部分,准备 ──
    "par":    ("准备,相等", "prepare, equal", "L. parare"),
    "part":   ("部分", "part", "L. pars"),

    # ── path / pass / pat : 感受,忍受 ──
    "path":   ("感受,忍受", "feel, suffer", "Gk. pathos"),
    "pati":   ("忍受", "suffer", "L. pati"),
    "pat":    ("忍受", "suffer, endure", "L. pati"),

    # ── ped / pod : 脚 ──
    "ped":    ("脚,教育", "foot, educate", "L. pes / Gk. pais"),
    "pod":    ("脚", "foot", "Gk. pous"),

    # ── pel / puls : 推,驱 ──
    "pel":    ("推,驱", "push, drive", "L. pellere"),
    "puls":   ("推,驱", "push, drive", "L. pellere"),

    # ── pend / pens / pond : 悬挂,称量,支付 ──
    "pend":   ("悬挂,支付", "hang, pay", "L. pendere"),
    "pens":   ("称量,思考", "weigh, think", "L. pensare"),
    "pond":   ("称量,思考", "weigh, think", "L. ponderare"),

    # ── pet / petit : 追求 ──
    "pet":    ("追求", "seek", "L. petere"),
    "petit":  ("追求", "seek", "L. petere"),

    # ── phil : 爱 ──
    "phil":   ("爱", "love", "Gk. philos"),

    # ── phon / phone : 声音 ──
    "phon":   ("声音", "sound, voice", "Gk. phone"),
    "phone":  ("声音", "sound, voice", "Gk. phone"),

    # ── photo / phos : 光 ──
    "photo":  ("光", "light", "Gk. phos"),
    "phos":   ("光", "light", "Gk. phos"),

    # ── plic / plex / ply / ploy / pli : 折叠 ──
    "plic":   ("折叠", "fold", "L. plicare"),
    "plex":   ("折叠", "fold", "L. plicare"),
    "ply":    ("折叠", "fold", "L. plicare"),
    "ploy":   ("折叠,运用", "fold, use", "L. plicare"),
    "pli":    ("折叠", "fold", "L. plicare"),

    # ── pon / pos / posit : 放置 ──
    "pon":    ("放置", "put, place", "L. ponere"),
    "pos":    ("放置", "put, place", "L. ponere"),
    "posit":  ("放置", "put, place", "L. ponere"),
    "pound":  ("放置", "put, place", "L. ponere"),

    # ── popul / publ : 人民 ──
    "popul":  ("人民", "people", "L. populus"),
    "publ":   ("公共", "public", "L. publicus"),

    # ── port : 携带,港口 ──
    "port":   ("携带", "carry", "L. portare"),

    # ── potent / poss : 有力 ──
    "potent": ("有力", "powerful", "L. potens"),
    "poss":   ("能够", "able", "L. posse"),

    # ── preci / prais / pric : 价值 ──
    "preci":  ("价值", "value, price", "L. pretium"),
    "prais":  ("价值,赞美", "value, praise", "L. pretium"),
    "pric":   ("价值", "value, price", "L. pretium"),

    # ── press : 压 ──
    "press":  ("压", "press", "L. pressare"),

    # ── prim / prem / prin : 第一 ──
    "prim":   ("第一", "first", "L. primus"),
    "prem":   ("第一", "first", "L. primus"),
    "prin":   ("第一", "first", "L. primus"),

    # ── priv : 私有 ──
    "priv":   ("私有", "private", "L. privatus"),

    # ── prob / prov : 证明,试验 ──
    "prob":   ("证明,试验", "prove, test", "L. probare"),
    "prov":   ("证明", "prove", "L. probare"),

    # ── proper / propri : 适当 ──
    "proper": ("适当", "proper, own", "L. proprius"),
    "propri": ("适当", "proper, own", "L. proprius"),

    # ── put / putat : 思考,计算 ──
    "put":    ("思考,计算", "think, reckon", "L. putare"),
    "putat":  ("思考", "think", "L. putare"),

    # ── quir / quisit / quest / quer : 寻找 ──
    "quir":   ("寻找", "seek, ask", "L. quaerere"),
    "quisit": ("寻找", "seek", "L. quaerere"),
    "quest":  ("寻找", "seek, ask", "L. quaerere"),
    "quer":   ("寻找", "seek", "L. quaerere"),

    # ── rect / reg : 直,统治 ──
    "rect":   ("直,正确", "straight, right", "L. rectus"),
    "reg":    ("统治,规则", "rule, govern", "L. rex"),
    "rul":    ("统治", "rule", "L. regula"),

    # ── rupt : 断裂 ──
    "rupt":   ("断裂", "break", "L. rumpere"),

    # ── sacr / secr / sanct : 神圣 ──
    "sacr":   ("神圣", "sacred", "L. sacer"),
    "secr":   ("秘密", "secret", "L. secretus"),
    "sanct":  ("神圣", "holy", "L. sanctus"),

    # ── scend / scens / scal : 攀登 ──
    "scend":  ("攀登", "climb", "L. scandere"),
    "scens":  ("攀登", "climb", "L. scandere"),
    "scal":   ("攀登", "climb", "L. scala"),

    # ── sci : 知道 ──
    "sci":    ("知道", "know", "L. scire"),

    # ── scrib / script : 写 ──
    "scrib":  ("写", "write", "L. scribere"),
    "script": ("写", "write", "L. scribere"),

    # ── sec / sect / seg : 切 ──
    "sec":    ("切", "cut", "L. secare"),
    "sect":   ("切", "cut", "L. secare"),
    "seg":    ("切", "cut", "L. secare"),

    # ── sens / sent : 感觉 ──
    "sens":   ("感觉", "feel, sense", "L. sentire"),
    "sent":   ("感觉", "feel, sense", "L. sentire"),

    # ── sequ / secut / su : 跟随 ──
    "sequ":   ("跟随", "follow", "L. sequi"),
    "secut":  ("跟随", "follow", "L. sequi"),
    "su":     ("跟随", "follow", "L. sequi"),

    # ── serv : 服务,保存 ──
    "serv":   ("服务,保存", "serve, keep", "L. servare"),

    # ── sign / signi : 标记 ──
    "sign":   ("标记", "sign, mark", "L. signum"),
    "signi":  ("标记", "sign, mark", "L. signum"),

    # ── simil / simul / sembl : 相似 ──
    "simil":  ("相似", "similar", "L. similis"),
    "simul":  ("相似,同时", "similar, at same time", "L. similis"),
    "sembl":  ("相似", "similar", "L. simulare"),

    # ── sist / sta / stit / stitut : 站立 ──
    "sist":   ("站立", "stand", "L. sistere"),
    "sta":    ("站立", "stand", "L. stare"),
    "stat":   ("站立", "stand", "L. stare"),
    "stit":   ("站立,建立", "stand, set up", "L. statuere"),
    "stitut": ("建立", "set up", "L. statuere"),

    # ── soci : 社会,同伴 ──
    "soci":   ("同伴,社会", "companion", "L. socius"),

    # ── sol : 独自,太阳 ──
    "sol":    ("独自,太阳", "alone, sun", "L. solus"),

    # ── solv / solu / solut : 松开 ──
    "solv":   ("松开,解决", "loosen, solve", "L. solvere"),
    "solu":   ("松开", "loosen", "L. solvere"),
    "solut":  ("松开,解决", "loosen, solve", "L. solvere"),

    # ── son : 声音 ──
    "son":    ("声音", "sound", "L. sonus"),

    # ── spec / spect / spic : 看 ──
    "spec":   ("看", "look, see", "L. specere"),
    "spect":  ("看", "look, see", "L. specere"),
    "spic":   ("看", "look, see", "L. specere"),

    # ── sper / spir : 希望,呼吸 ──
    "sper":   ("希望", "hope", "L. sperare"),
    "spir":   ("呼吸", "breathe", "L. spirare"),

    # ── string / strict / strain / stress : 拉紧 ──
    "string": ("拉紧", "draw tight", "L. stringere"),
    "strict": ("拉紧", "draw tight", "L. stringere"),
    "strain": ("拉紧", "draw tight", "L. stringere"),
    "stress": ("拉紧,压力", "draw tight", "L. stringere"),

    # ── stru / struct : 建造 ──
    "stru":   ("建造", "build", "L. struere"),
    "struct": ("建造", "build", "L. struere"),

    # ── sum / sumpt : 拿取 ──
    "sum":    ("拿取", "take", "L. sumere"),
    "sumpt":  ("拿取", "take", "L. sumere"),

    # ── tact / tang / tag / tig / ting : 接触 ──
    "tact":   ("接触", "touch", "L. tangere"),
    "tang":   ("接触", "touch", "L. tangere"),
    "tag":    ("接触", "touch", "L. tangere"),
    "tig":    ("接触", "touch", "L. tangere"),
    "ting":   ("接触", "touch", "L. tangere"),

    # ── tain / ten / tin / tent : 保持 ──
    "tain":   ("保持,握", "hold, keep", "L. tenere"),
    "ten":    ("保持,握", "hold, keep", "L. tenere"),
    "tin":    ("保持,握", "hold, keep", "L. tenere"),
    "tent":   ("保持,握", "hold, keep", "L. tenere"),

    # ── techn / techno : 技术 ──
    "techn":  ("技术", "skill, art", "Gk. techne"),
    "techno": ("技术", "skill, art", "Gk. techne"),

    # ── temp / tempor : 时间 ──
    "temp":   ("时间", "time", "L. tempus"),
    "tempor": ("时间", "time", "L. tempus"),

    # ── tend / tens / tent : 伸展 ──
    "tend":   ("伸展", "stretch", "L. tendere"),
    "tens":   ("伸展", "stretch", "L. tendere"),

    # ── tect : 覆盖,保护 ──
    "tect":   ("覆盖,保护", "cover, protect", "L. tegere"),

    # ── termin : 界限 ──
    "termin": ("界限,终结", "boundary, end", "L. terminus"),

    # ── terr : 地 ──
    "terr":   ("地", "earth, land", "L. terra"),

    # ── test : 证据 ──
    "test":   ("证据,测试", "witness", "L. testis"),

    # ── text : 编织 ──
    "text":   ("编织", "weave", "L. texere"),

    # ── the / theo : 神 ──
    "the":    ("神", "god", "Gk. theos"),
    "theo":   ("神", "god", "Gk. theos"),

    # ── therm : 热 ──
    "therm":  ("热", "heat", "Gk. therme"),

    # ── tort / torqu : 扭转 ──
    "tort":   ("扭转", "twist", "L. torquere"),
    "torqu":  ("扭转", "twist", "L. torquere"),

    # ── tract / tra : 拉,拖 ──
    "tract":  ("拉,拖", "pull, draw", "L. trahere"),

    # ── trib / tribut : 给予 ──
    "trib":   ("给予", "give, assign", "L. tribuere"),
    "tribut": ("给予", "give, assign", "L. tribuere"),

    # ── turb : 搅乱 ──
    "turb":   ("搅乱", "disturb", "L. turbare"),

    # ── typ : 类型 ──
    "typ":    ("类型", "type", "Gk. typos"),

    # ── vac / van / void : 空 ──
    "vac":    ("空", "empty", "L. vacare"),
    "van":    ("空", "empty, vain", "L. vanus"),
    "void":   ("空", "empty", "L. vocitus"),

    # ── val / vail : 有力,价值 ──
    "val":    ("有力,价值", "strong, worth", "L. valere"),
    "vail":   ("有力,价值", "strong, worth", "L. valere"),

    # ── var / vari : 变化 ──
    "var":    ("变化", "change", "L. varius"),
    "vari":   ("变化", "change", "L. varius"),

    # ── ven / vent : 来 ──
    "ven":    ("来", "come", "L. venire"),
    "vent":   ("来", "come", "L. venire"),

    # ── ver / veri : 真实 ──
    "ver":    ("真实", "true", "L. verus"),
    "veri":   ("真实", "true", "L. verus"),

    # ── verb : 词语 ──
    "verb":   ("词语", "word", "L. verbum"),

    # ── vert / vers : 转 ──
    "vert":   ("转", "turn", "L. vertere"),
    "vers":   ("转", "turn", "L. vertere"),

    # ── vi / via / voy : 路 ──
    "vi":     ("路", "way, road", "L. via"),
    "via":    ("路", "way, road", "L. via"),
    "voy":    ("路,旅行", "way, journey", "L. via"),

    # ── vid / vis : 看 ──
    "vid":    ("看", "see", "L. videre"),
    "vis":    ("看", "see", "L. videre"),
    "view":   ("看", "see", "L. videre"),

    # ── vinc / vict : 征服 ──
    "vinc":   ("征服", "conquer", "L. vincere"),
    "vict":   ("征服", "conquer", "L. vincere"),

    # ── viv / vit / vig : 生命,活力 ──
    "viv":    ("生命,活", "live", "L. vivere"),
    "vit":    ("生命", "life", "L. vita"),
    "vig":    ("活力", "lively", "L. vigere"),

    # ── voc / vok / voic : 叫,声音 ──
    "voc":    ("叫,声音", "call, voice", "L. vocare"),
    "vok":    ("叫", "call", "L. vocare"),
    "voic":   ("声音", "voice", "L. vox"),

    # ── vol / volv / volut : 卷,转 ──
    "vol":    ("意愿,飞", "will, fly", "L. velle"),
    "volv":   ("卷,转", "roll, turn", "L. volvere"),
    "volut":  ("卷,转", "roll, turn", "L. volvere"),

    # ── vor / vour : 吃 ──
    "vor":    ("吃", "eat, devour", "L. vorare"),
    "vour":   ("吃", "eat, devour", "L. vorare"),
}

# ══════════════════════════════════════════════════════════════
# 后缀数据库  { 后缀: (含义_中文, 词性, 含义_英文) }
# ══════════════════════════════════════════════════════════════

SUFFIXES: dict[str, tuple[str, str, str]] = {
    # ── 名词后缀 ──
    "tion":   ("行为,状态", "n.", "act, state"),
    "sion":   ("行为,状态", "n.", "act, state"),
    "ion":    ("行为,状态", "n.", "act, state"),
    "ation":  ("行为,过程", "n.", "act, process"),
    "ition":  ("行为,状态", "n.", "act, state"),
    "ment":   ("行为,结果", "n.", "act, result"),
    "ness":   ("性质,状态", "n.", "quality, state"),
    "ity":    ("性质,状态", "n.", "quality, state"),
    "ty":     ("性质,状态", "n.", "quality, state"),
    "ance":   ("性质,状态", "n.", "quality, state"),
    "ence":   ("性质,状态", "n.", "quality, state"),
    "ancy":   ("性质,状态", "n.", "quality, state"),
    "ency":   ("性质,状态", "n.", "quality, state"),
    "dom":    ("领域,状态", "n.", "domain, state"),
    "ship":   ("身份,关系", "n.", "status, relation"),
    "age":    ("行为,集合", "n.", "act, collection"),
    "ure":    ("行为,结果", "n.", "act, result"),
    "ery":    ("场所,行为", "n.", "place, practice"),
    "ory":    ("场所,物", "n.", "place, thing"),
    "ary":    ("场所,人", "n.", "place, person"),
    "er":     ("做…的人/物", "n.", "one who"),
    "or":     ("做…的人/物", "n.", "one who"),
    "ar":     ("做…的人/物", "n.", "one who"),
    "ist":    ("做…的人", "n.", "one who"),
    "ant":    ("做…的人/物", "n.", "one who"),
    "ent":    ("做…的人/物", "n.", "one who"),
    "ee":     ("被…的人", "n.", "one who is"),
    "ism":    ("主义,学说", "n.", "doctrine, belief"),
    "al":     ("行为", "n.", "act of"),
    "ics":    ("学科", "n.", "science of"),
    "logy":   ("学科", "n.", "study of"),
    "ium":    ("场所,物质", "n.", "place, element"),
    "tude":   ("状态", "n.", "state of"),
    "th":     ("过程,状态", "n.", "process, state"),
    "ing":    ("行为,过程", "n./a.", "act, process"),

    # ── 动词后缀 ──
    "ate":    ("使,做", "v.", "make, do"),
    "ify":    ("使成为", "v.", "make"),
    "ize":    ("使成为", "v.", "make"),
    "ise":    ("使成为", "v.", "make"),
    "en":     ("使成为", "v.", "make"),
    "ish":    ("做", "v./a.", "do, make"),

    # ── 形容词后缀 ──
    "able":   ("能…的", "a.", "able to be"),
    "ible":   ("能…的", "a.", "able to be"),
    "al":     ("…的", "a.", "relating to"),
    "ial":    ("…的", "a.", "relating to"),
    "ical":   ("…的", "a.", "relating to"),
    "ful":    ("充满…的", "a.", "full of"),
    "ive":    ("有…性质的", "a.", "tending to"),
    "ative":  ("有…性质的", "a.", "tending to"),
    "itive":  ("有…性质的", "a.", "tending to"),
    "less":   ("无…的", "a.", "without"),
    "ous":    ("充满…的", "a.", "full of"),
    "ious":   ("充满…的", "a.", "full of"),
    "eous":   ("充满…的", "a.", "full of"),
    "ic":     ("…的", "a.", "relating to"),
    "ent":    ("…的", "a.", "having quality"),
    "ant":    ("…的", "a.", "having quality"),
    "ary":    ("…的", "a.", "relating to"),
    "ory":    ("…的", "a.", "relating to"),
    "ular":   ("…的", "a.", "relating to"),
    "ile":    ("能…的", "a.", "able to"),
    "ine":    ("…的", "a.", "relating to"),

    # ── 副词后缀 ──
    "ly":     ("…地", "ad.", "in manner of"),
    "ward":   ("向…", "ad.", "toward"),
    "wards":  ("向…", "ad.", "toward"),
    "wise":   ("方式", "ad.", "in manner of"),
}


# ══════════════════════════════════════════════════════════════
# 手工标注：高频词的精准分解（确保核心词汇100%准确）
# ══════════════════════════════════════════════════════════════

MANUAL_MORPHEMES: dict[str, list[dict]] = {
    "acceptance": [
        {"part": "ac", "type": "prefix", "meaning": "向", "origin": "ad-"},
        {"part": "cept", "type": "root", "meaning": "拿,取", "origin": "L.capere"},
        {"part": "ance", "type": "suffix", "meaning": "名词后缀", "origin": ""},
    ],
    "accident": [
        {"part": "ac", "type": "prefix", "meaning": "向", "origin": "ad-"},
        {"part": "cid", "type": "root", "meaning": "落下,发生", "origin": "L.cadere"},
        {"part": "ent", "type": "suffix", "meaning": "…的", "origin": ""},
    ],
    "accidentally": [
        {"part": "ac", "type": "prefix", "meaning": "向", "origin": "ad-"},
        {"part": "cid", "type": "root", "meaning": "落下,发生", "origin": "L.cadere"},
        {"part": "ent", "type": "suffix", "meaning": "…的", "origin": ""},
        {"part": "al", "type": "suffix", "meaning": "…的", "origin": ""},
        {"part": "ly", "type": "suffix", "meaning": "…地", "origin": ""},
    ],
    "accommodate": [
        {"part": "ac", "type": "prefix", "meaning": "向", "origin": "ad-"},
        {"part": "com", "type": "prefix", "meaning": "共同", "origin": "com-"},
        {"part": "mod", "type": "root", "meaning": "方式,适度", "origin": "L.modus"},
        {"part": "ate", "type": "suffix", "meaning": "使,做", "origin": ""},
    ],
    "accompany": [
        {"part": "ac", "type": "prefix", "meaning": "向", "origin": "ad-"},
        {"part": "com", "type": "prefix", "meaning": "共同", "origin": "com-"},
        {"part": "pan", "type": "root", "meaning": "面包→伴侣", "origin": "L.panis"},
        {"part": "y", "type": "suffix", "meaning": "动词后缀", "origin": ""},
    ],
    "accomplish": [
        {"part": "ac", "type": "prefix", "meaning": "向", "origin": "ad-"},
        {"part": "com", "type": "prefix", "meaning": "完全", "origin": "com-"},
        {"part": "pl", "type": "root", "meaning": "填满", "origin": "L.plere"},
        {"part": "ish", "type": "suffix", "meaning": "做", "origin": ""},
    ],
    "accumulate": [
        {"part": "ac", "type": "prefix", "meaning": "向", "origin": "ad-"},
        {"part": "cumul", "type": "root", "meaning": "堆积", "origin": "L.cumulus"},
        {"part": "ate", "type": "suffix", "meaning": "使,做", "origin": ""},
    ],
    "accurate": [
        {"part": "ac", "type": "prefix", "meaning": "向", "origin": "ad-"},
        {"part": "cur", "type": "root", "meaning": "关心", "origin": "L.cura"},
        {"part": "ate", "type": "suffix", "meaning": "…的", "origin": ""},
    ],
    "accurately": [
        {"part": "ac", "type": "prefix", "meaning": "向", "origin": "ad-"},
        {"part": "cur", "type": "root", "meaning": "关心", "origin": "L.cura"},
        {"part": "ate", "type": "suffix", "meaning": "…的", "origin": ""},
        {"part": "ly", "type": "suffix", "meaning": "…地", "origin": ""},
    ],
    "accuracy": [
        {"part": "ac", "type": "prefix", "meaning": "向", "origin": "ad-"},
        {"part": "cur", "type": "root", "meaning": "关心", "origin": "L.cura"},
        {"part": "acy", "type": "suffix", "meaning": "性质,状态", "origin": ""},
    ],
    "achievement": [
        {"part": "achieve", "type": "root", "meaning": "达成", "origin": "OF.achever"},
        {"part": "ment", "type": "suffix", "meaning": "行为,结果", "origin": ""},
    ],
    "acknowledge": [
        {"part": "ac", "type": "prefix", "meaning": "向", "origin": "ad-"},
        {"part": "know", "type": "root", "meaning": "知道", "origin": "OE.cnawan"},
        {"part": "ledge", "type": "suffix", "meaning": "名词后缀", "origin": ""},
    ],
    "actually": [
        {"part": "act", "type": "root", "meaning": "做,行动", "origin": "L.agere"},
        {"part": "ual", "type": "suffix", "meaning": "…的", "origin": ""},
        {"part": "ly", "type": "suffix", "meaning": "…地", "origin": ""},
    ],
    "addition": [
        {"part": "ad", "type": "prefix", "meaning": "向", "origin": "ad-"},
        {"part": "dit", "type": "root", "meaning": "给", "origin": "L.dare"},
        {"part": "ion", "type": "suffix", "meaning": "行为,状态", "origin": ""},
    ],
    "adjust": [
        {"part": "ad", "type": "prefix", "meaning": "向", "origin": "ad-"},
        {"part": "just", "type": "root", "meaning": "公正", "origin": "L.justus"},
    ],
    "administration": [
        {"part": "ad", "type": "prefix", "meaning": "向", "origin": "ad-"},
        {"part": "ministr", "type": "root", "meaning": "服务,管理", "origin": "L.minister"},
        {"part": "ation", "type": "suffix", "meaning": "行为,过程", "origin": ""},
    ],
    "admission": [
        {"part": "ad", "type": "prefix", "meaning": "向", "origin": "ad-"},
        {"part": "miss", "type": "root", "meaning": "送,发", "origin": "L.mittere"},
        {"part": "ion", "type": "suffix", "meaning": "行为,状态", "origin": ""},
    ],
    "advantage": [
        {"part": "ad", "type": "prefix", "meaning": "向", "origin": "ad-"},
        {"part": "vant", "type": "root", "meaning": "前面", "origin": "L.abante"},
        {"part": "age", "type": "suffix", "meaning": "行为,状态", "origin": ""},
    ],
    "advertisement": [
        {"part": "ad", "type": "prefix", "meaning": "向", "origin": "ad-"},
        {"part": "vert", "type": "root", "meaning": "转", "origin": "L.vertere"},
        {"part": "ise", "type": "suffix", "meaning": "使成为", "origin": ""},
        {"part": "ment", "type": "suffix", "meaning": "行为,结果", "origin": ""},
    ],
    "agreement": [
        {"part": "a", "type": "prefix", "meaning": "向", "origin": "ad-"},
        {"part": "gree", "type": "root", "meaning": "喜悦,同意", "origin": "L.gratus"},
        {"part": "ment", "type": "suffix", "meaning": "行为,结果", "origin": ""},
    ],
    "agriculture": [
        {"part": "agri", "type": "root", "meaning": "田地", "origin": "L.ager"},
        {"part": "cult", "type": "root", "meaning": "耕种", "origin": "L.colere"},
        {"part": "ure", "type": "suffix", "meaning": "行为,结果", "origin": ""},
    ],
    "announcement": [
        {"part": "an", "type": "prefix", "meaning": "向", "origin": "ad-"},
        {"part": "nounc", "type": "root", "meaning": "报告", "origin": "L.nuntiare"},
        {"part": "ment", "type": "suffix", "meaning": "行为,结果", "origin": ""},
    ],
    "appearance": [
        {"part": "ap", "type": "prefix", "meaning": "向", "origin": "ad-"},
        {"part": "pear", "type": "root", "meaning": "出现", "origin": "L.parere"},
        {"part": "ance", "type": "suffix", "meaning": "性质,状态", "origin": ""},
    ],
    "application": [
        {"part": "ap", "type": "prefix", "meaning": "向", "origin": "ad-"},
        {"part": "plic", "type": "root", "meaning": "折叠,应用", "origin": "L.plicare"},
        {"part": "ation", "type": "suffix", "meaning": "行为,过程", "origin": ""},
    ],
    "appreciate": [
        {"part": "ap", "type": "prefix", "meaning": "向", "origin": "ad-"},
        {"part": "preci", "type": "root", "meaning": "价值", "origin": "L.pretium"},
        {"part": "ate", "type": "suffix", "meaning": "使,做", "origin": ""},
    ],
    "approach": [
        {"part": "ap", "type": "prefix", "meaning": "向", "origin": "ad-"},
        {"part": "proach", "type": "root", "meaning": "接近", "origin": "L.prope"},
    ],
    "appropriate": [
        {"part": "ap", "type": "prefix", "meaning": "向", "origin": "ad-"},
        {"part": "propri", "type": "root", "meaning": "适当,自己的", "origin": "L.proprius"},
        {"part": "ate", "type": "suffix", "meaning": "…的", "origin": ""},
    ],
    "arrangement": [
        {"part": "ar", "type": "prefix", "meaning": "向", "origin": "ad-"},
        {"part": "range", "type": "root", "meaning": "排列", "origin": "OF.rangier"},
        {"part": "ment", "type": "suffix", "meaning": "行为,结果", "origin": ""},
    ],
    "assumption": [
        {"part": "as", "type": "prefix", "meaning": "向", "origin": "ad-"},
        {"part": "sumpt", "type": "root", "meaning": "拿取", "origin": "L.sumere"},
        {"part": "ion", "type": "suffix", "meaning": "行为,状态", "origin": ""},
    ],
    "attention": [
        {"part": "at", "type": "prefix", "meaning": "向", "origin": "ad-"},
        {"part": "tent", "type": "root", "meaning": "伸展", "origin": "L.tendere"},
        {"part": "ion", "type": "suffix", "meaning": "行为,状态", "origin": ""},
    ],
    "attraction": [
        {"part": "at", "type": "prefix", "meaning": "向", "origin": "ad-"},
        {"part": "tract", "type": "root", "meaning": "拉,拖", "origin": "L.trahere"},
        {"part": "ion", "type": "suffix", "meaning": "行为,状态", "origin": ""},
    ],
    "beautiful": [
        {"part": "beauti", "type": "root", "meaning": "美", "origin": "OF.bealte"},
        {"part": "ful", "type": "suffix", "meaning": "充满…的", "origin": ""},
    ],
    "celebration": [
        {"part": "celebr", "type": "root", "meaning": "庆祝,著名", "origin": "L.celebrare"},
        {"part": "ation", "type": "suffix", "meaning": "行为,过程", "origin": ""},
    ],
    "comfortable": [
        {"part": "com", "type": "prefix", "meaning": "完全", "origin": "com-"},
        {"part": "fort", "type": "root", "meaning": "强", "origin": "L.fortis"},
        {"part": "able", "type": "suffix", "meaning": "能…的", "origin": ""},
    ],
    "communication": [
        {"part": "com", "type": "prefix", "meaning": "共同", "origin": "com-"},
        {"part": "mun", "type": "root", "meaning": "公共,服务", "origin": "L.munus"},
        {"part": "ic", "type": "suffix", "meaning": "…的", "origin": ""},
        {"part": "ation", "type": "suffix", "meaning": "行为,过程", "origin": ""},
    ],
    "competition": [
        {"part": "com", "type": "prefix", "meaning": "共同", "origin": "com-"},
        {"part": "pet", "type": "root", "meaning": "追求", "origin": "L.petere"},
        {"part": "ition", "type": "suffix", "meaning": "行为,状态", "origin": ""},
    ],
    "concentration": [
        {"part": "con", "type": "prefix", "meaning": "共同", "origin": "com-"},
        {"part": "centr", "type": "root", "meaning": "中心", "origin": "L.centrum"},
        {"part": "ation", "type": "suffix", "meaning": "行为,过程", "origin": ""},
    ],
    "conclusion": [
        {"part": "con", "type": "prefix", "meaning": "完全", "origin": "com-"},
        {"part": "clus", "type": "root", "meaning": "关闭", "origin": "L.claudere"},
        {"part": "ion", "type": "suffix", "meaning": "行为,状态", "origin": ""},
    ],
    "condition": [
        {"part": "con", "type": "prefix", "meaning": "共同", "origin": "com-"},
        {"part": "dit", "type": "root", "meaning": "说,给", "origin": "L.dicere"},
        {"part": "ion", "type": "suffix", "meaning": "行为,状态", "origin": ""},
    ],
    "confidence": [
        {"part": "con", "type": "prefix", "meaning": "完全", "origin": "com-"},
        {"part": "fid", "type": "root", "meaning": "信任", "origin": "L.fides"},
        {"part": "ence", "type": "suffix", "meaning": "性质,状态", "origin": ""},
    ],
    "confirmation": [
        {"part": "con", "type": "prefix", "meaning": "完全", "origin": "com-"},
        {"part": "firm", "type": "root", "meaning": "坚固", "origin": "L.firmus"},
        {"part": "ation", "type": "suffix", "meaning": "行为,过程", "origin": ""},
    ],
    "connection": [
        {"part": "con", "type": "prefix", "meaning": "共同", "origin": "com-"},
        {"part": "nect", "type": "root", "meaning": "绑,连", "origin": "L.nectere"},
        {"part": "ion", "type": "suffix", "meaning": "行为,状态", "origin": ""},
    ],
    "consideration": [
        {"part": "con", "type": "prefix", "meaning": "完全", "origin": "com-"},
        {"part": "sider", "type": "root", "meaning": "星,思考", "origin": "L.sidus"},
        {"part": "ation", "type": "suffix", "meaning": "行为,过程", "origin": ""},
    ],
    "construction": [
        {"part": "con", "type": "prefix", "meaning": "共同", "origin": "com-"},
        {"part": "struct", "type": "root", "meaning": "建造", "origin": "L.struere"},
        {"part": "ion", "type": "suffix", "meaning": "行为,状态", "origin": ""},
    ],
    "contribution": [
        {"part": "con", "type": "prefix", "meaning": "共同", "origin": "com-"},
        {"part": "tribut", "type": "root", "meaning": "给予", "origin": "L.tribuere"},
        {"part": "ion", "type": "suffix", "meaning": "行为,状态", "origin": ""},
    ],
    "conversation": [
        {"part": "con", "type": "prefix", "meaning": "共同", "origin": "com-"},
        {"part": "vers", "type": "root", "meaning": "转", "origin": "L.vertere"},
        {"part": "ation", "type": "suffix", "meaning": "行为,过程", "origin": ""},
    ],
    "correction": [
        {"part": "cor", "type": "prefix", "meaning": "共同,完全", "origin": "com-"},
        {"part": "rect", "type": "root", "meaning": "直,正确", "origin": "L.rectus"},
        {"part": "ion", "type": "suffix", "meaning": "行为,状态", "origin": ""},
    ],
    "decoration": [
        {"part": "decor", "type": "root", "meaning": "装饰,美", "origin": "L.decorus"},
        {"part": "ation", "type": "suffix", "meaning": "行为,过程", "origin": ""},
    ],
    "description": [
        {"part": "de", "type": "prefix", "meaning": "向下", "origin": "de-"},
        {"part": "script", "type": "root", "meaning": "写", "origin": "L.scribere"},
        {"part": "ion", "type": "suffix", "meaning": "行为,状态", "origin": ""},
    ],
    "determination": [
        {"part": "de", "type": "prefix", "meaning": "完全", "origin": "de-"},
        {"part": "termin", "type": "root", "meaning": "界限", "origin": "L.terminus"},
        {"part": "ation", "type": "suffix", "meaning": "行为,过程", "origin": ""},
    ],
    "development": [
        {"part": "de", "type": "prefix", "meaning": "去除", "origin": "de-"},
        {"part": "velop", "type": "root", "meaning": "包裹→展开", "origin": "OF.voloper"},
        {"part": "ment", "type": "suffix", "meaning": "行为,结果", "origin": ""},
    ],
    "difference": [
        {"part": "dif", "type": "prefix", "meaning": "分开", "origin": "dis-"},
        {"part": "fer", "type": "root", "meaning": "带,承载", "origin": "L.ferre"},
        {"part": "ence", "type": "suffix", "meaning": "性质,状态", "origin": ""},
    ],
    "direction": [
        {"part": "di", "type": "prefix", "meaning": "分开", "origin": "dis-"},
        {"part": "rect", "type": "root", "meaning": "直,引导", "origin": "L.rectus"},
        {"part": "ion", "type": "suffix", "meaning": "行为,状态", "origin": ""},
    ],
    "disadvantage": [
        {"part": "dis", "type": "prefix", "meaning": "否定", "origin": "dis-"},
        {"part": "ad", "type": "prefix", "meaning": "向", "origin": "ad-"},
        {"part": "vant", "type": "root", "meaning": "前面", "origin": "L.abante"},
        {"part": "age", "type": "suffix", "meaning": "行为,状态", "origin": ""},
    ],
    "disappoint": [
        {"part": "dis", "type": "prefix", "meaning": "否定", "origin": "dis-"},
        {"part": "ap", "type": "prefix", "meaning": "向", "origin": "ad-"},
        {"part": "point", "type": "root", "meaning": "指定", "origin": "L.punctum"},
    ],
    "discovery": [
        {"part": "dis", "type": "prefix", "meaning": "去除", "origin": "dis-"},
        {"part": "cover", "type": "root", "meaning": "覆盖", "origin": "L.cooperire"},
        {"part": "y", "type": "suffix", "meaning": "名词后缀", "origin": ""},
    ],
    "discussion": [
        {"part": "dis", "type": "prefix", "meaning": "分开", "origin": "dis-"},
        {"part": "cuss", "type": "root", "meaning": "摇,打", "origin": "L.quatere"},
        {"part": "ion", "type": "suffix", "meaning": "行为,状态", "origin": ""},
    ],
    "education": [
        {"part": "e", "type": "prefix", "meaning": "出", "origin": "ex-"},
        {"part": "duc", "type": "root", "meaning": "引导", "origin": "L.ducere"},
        {"part": "ation", "type": "suffix", "meaning": "行为,过程", "origin": ""},
    ],
    "employment": [
        {"part": "em", "type": "prefix", "meaning": "使成为", "origin": "en-"},
        {"part": "ploy", "type": "root", "meaning": "折叠,运用", "origin": "L.plicare"},
        {"part": "ment", "type": "suffix", "meaning": "行为,结果", "origin": ""},
    ],
    "encouragement": [
        {"part": "en", "type": "prefix", "meaning": "使成为", "origin": "en-"},
        {"part": "cour", "type": "root", "meaning": "心,勇气", "origin": "L.cor"},
        {"part": "age", "type": "suffix", "meaning": "行为,状态", "origin": ""},
        {"part": "ment", "type": "suffix", "meaning": "行为,结果", "origin": ""},
    ],
    "environment": [
        {"part": "en", "type": "prefix", "meaning": "使成为", "origin": "en-"},
        {"part": "viron", "type": "root", "meaning": "周围", "origin": "OF.viron"},
        {"part": "ment", "type": "suffix", "meaning": "行为,结果", "origin": ""},
    ],
    "equipment": [
        {"part": "equip", "type": "root", "meaning": "装备", "origin": "ON.skipa"},
        {"part": "ment", "type": "suffix", "meaning": "行为,结果", "origin": ""},
    ],
    "examination": [
        {"part": "ex", "type": "prefix", "meaning": "出", "origin": "ex-"},
        {"part": "amin", "type": "root", "meaning": "检查", "origin": "L.examinare"},
        {"part": "ation", "type": "suffix", "meaning": "行为,过程", "origin": ""},
    ],
    "excitement": [
        {"part": "ex", "type": "prefix", "meaning": "出", "origin": "ex-"},
        {"part": "cit", "type": "root", "meaning": "引发,召唤", "origin": "L.citare"},
        {"part": "ment", "type": "suffix", "meaning": "行为,结果", "origin": ""},
    ],
    "expectation": [
        {"part": "ex", "type": "prefix", "meaning": "出", "origin": "ex-"},
        {"part": "spect", "type": "root", "meaning": "看", "origin": "L.specere"},
        {"part": "ation", "type": "suffix", "meaning": "行为,过程", "origin": ""},
    ],
    "experience": [
        {"part": "ex", "type": "prefix", "meaning": "出", "origin": "ex-"},
        {"part": "peri", "type": "root", "meaning": "尝试", "origin": "L.periri"},
        {"part": "ence", "type": "suffix", "meaning": "性质,状态", "origin": ""},
    ],
    "explanation": [
        {"part": "ex", "type": "prefix", "meaning": "出", "origin": "ex-"},
        {"part": "plan", "type": "root", "meaning": "平,展开", "origin": "L.planus"},
        {"part": "ation", "type": "suffix", "meaning": "行为,过程", "origin": ""},
    ],
    "expression": [
        {"part": "ex", "type": "prefix", "meaning": "出", "origin": "ex-"},
        {"part": "press", "type": "root", "meaning": "压", "origin": "L.pressare"},
        {"part": "ion", "type": "suffix", "meaning": "行为,状态", "origin": ""},
    ],
    "generation": [
        {"part": "gen", "type": "root", "meaning": "产生", "origin": "L.generare"},
        {"part": "er", "type": "suffix", "meaning": "做…的", "origin": ""},
        {"part": "ation", "type": "suffix", "meaning": "行为,过程", "origin": ""},
    ],
    "government": [
        {"part": "govern", "type": "root", "meaning": "统治,管理", "origin": "L.gubernare"},
        {"part": "ment", "type": "suffix", "meaning": "行为,结果", "origin": ""},
    ],
    "imagination": [
        {"part": "imagin", "type": "root", "meaning": "形象,想象", "origin": "L.imago"},
        {"part": "ation", "type": "suffix", "meaning": "行为,过程", "origin": ""},
    ],
    "immediately": [
        {"part": "im", "type": "prefix", "meaning": "不", "origin": "in-"},
        {"part": "medi", "type": "root", "meaning": "中间", "origin": "L.medius"},
        {"part": "ate", "type": "suffix", "meaning": "…的", "origin": ""},
        {"part": "ly", "type": "suffix", "meaning": "…地", "origin": ""},
    ],
    "importance": [
        {"part": "im", "type": "prefix", "meaning": "向内", "origin": "in-"},
        {"part": "port", "type": "root", "meaning": "携带", "origin": "L.portare"},
        {"part": "ance", "type": "suffix", "meaning": "性质,状态", "origin": ""},
    ],
    "impossible": [
        {"part": "im", "type": "prefix", "meaning": "不", "origin": "in-"},
        {"part": "poss", "type": "root", "meaning": "能够", "origin": "L.posse"},
        {"part": "ible", "type": "suffix", "meaning": "能…的", "origin": ""},
    ],
    "impression": [
        {"part": "im", "type": "prefix", "meaning": "向内", "origin": "in-"},
        {"part": "press", "type": "root", "meaning": "压", "origin": "L.pressare"},
        {"part": "ion", "type": "suffix", "meaning": "行为,状态", "origin": ""},
    ],
    "improvement": [
        {"part": "im", "type": "prefix", "meaning": "向内", "origin": "in-"},
        {"part": "prov", "type": "root", "meaning": "证明→利益", "origin": "L.probare"},
        {"part": "ment", "type": "suffix", "meaning": "行为,结果", "origin": ""},
    ],
    "independence": [
        {"part": "in", "type": "prefix", "meaning": "不", "origin": "in-"},
        {"part": "de", "type": "prefix", "meaning": "向下", "origin": "de-"},
        {"part": "pend", "type": "root", "meaning": "悬挂", "origin": "L.pendere"},
        {"part": "ence", "type": "suffix", "meaning": "性质,状态", "origin": ""},
    ],
    "independent": [
        {"part": "in", "type": "prefix", "meaning": "不", "origin": "in-"},
        {"part": "de", "type": "prefix", "meaning": "向下", "origin": "de-"},
        {"part": "pend", "type": "root", "meaning": "悬挂", "origin": "L.pendere"},
        {"part": "ent", "type": "suffix", "meaning": "…的", "origin": ""},
    ],
    "indication": [
        {"part": "in", "type": "prefix", "meaning": "向内", "origin": "in-"},
        {"part": "dic", "type": "root", "meaning": "说,指", "origin": "L.dicere"},
        {"part": "ation", "type": "suffix", "meaning": "行为,过程", "origin": ""},
    ],
    "information": [
        {"part": "in", "type": "prefix", "meaning": "向内", "origin": "in-"},
        {"part": "form", "type": "root", "meaning": "形状,形成", "origin": "L.forma"},
        {"part": "ation", "type": "suffix", "meaning": "行为,过程", "origin": ""},
    ],
    "inspiration": [
        {"part": "in", "type": "prefix", "meaning": "向内", "origin": "in-"},
        {"part": "spir", "type": "root", "meaning": "呼吸", "origin": "L.spirare"},
        {"part": "ation", "type": "suffix", "meaning": "行为,过程", "origin": ""},
    ],
    "instruction": [
        {"part": "in", "type": "prefix", "meaning": "向内", "origin": "in-"},
        {"part": "struct", "type": "root", "meaning": "建造", "origin": "L.struere"},
        {"part": "ion", "type": "suffix", "meaning": "行为,状态", "origin": ""},
    ],
    "intelligence": [
        {"part": "inter", "type": "prefix", "meaning": "之间", "origin": "inter-"},
        {"part": "lig", "type": "root", "meaning": "选,读", "origin": "L.legere"},
        {"part": "ence", "type": "suffix", "meaning": "性质,状态", "origin": ""},
    ],
    "international": [
        {"part": "inter", "type": "prefix", "meaning": "之间", "origin": "inter-"},
        {"part": "nat", "type": "root", "meaning": "出生,国家", "origin": "L.nasci"},
        {"part": "ion", "type": "suffix", "meaning": "行为,状态", "origin": ""},
        {"part": "al", "type": "suffix", "meaning": "…的", "origin": ""},
    ],
    "introduction": [
        {"part": "intro", "type": "prefix", "meaning": "向内", "origin": "intro-"},
        {"part": "duct", "type": "root", "meaning": "引导", "origin": "L.ducere"},
        {"part": "ion", "type": "suffix", "meaning": "行为,状态", "origin": ""},
    ],
    "investigation": [
        {"part": "in", "type": "prefix", "meaning": "向内", "origin": "in-"},
        {"part": "vestig", "type": "root", "meaning": "追踪", "origin": "L.vestigare"},
        {"part": "ation", "type": "suffix", "meaning": "行为,过程", "origin": ""},
    ],
    "movement": [
        {"part": "mov", "type": "root", "meaning": "移动", "origin": "L.movere"},
        {"part": "ment", "type": "suffix", "meaning": "行为,结果", "origin": ""},
    ],
    "observation": [
        {"part": "ob", "type": "prefix", "meaning": "向", "origin": "ob-"},
        {"part": "serv", "type": "root", "meaning": "保存,观察", "origin": "L.servare"},
        {"part": "ation", "type": "suffix", "meaning": "行为,过程", "origin": ""},
    ],
    "operation": [
        {"part": "oper", "type": "root", "meaning": "工作", "origin": "L.operari"},
        {"part": "ation", "type": "suffix", "meaning": "行为,过程", "origin": ""},
    ],
    "opportunity": [
        {"part": "op", "type": "prefix", "meaning": "向", "origin": "ob-"},
        {"part": "port", "type": "root", "meaning": "港口→机会", "origin": "L.portus"},
        {"part": "un", "type": "root", "meaning": "合适", "origin": "L.opportunus"},
        {"part": "ity", "type": "suffix", "meaning": "性质,状态", "origin": ""},
    ],
    "organization": [
        {"part": "organ", "type": "root", "meaning": "器官,组织", "origin": "Gk.organon"},
        {"part": "iz", "type": "suffix", "meaning": "使成为", "origin": ""},
        {"part": "ation", "type": "suffix", "meaning": "行为,过程", "origin": ""},
    ],
    "participate": [
        {"part": "part", "type": "root", "meaning": "部分", "origin": "L.pars"},
        {"part": "cip", "type": "root", "meaning": "拿,取", "origin": "L.capere"},
        {"part": "ate", "type": "suffix", "meaning": "使,做", "origin": ""},
    ],
    "performance": [
        {"part": "per", "type": "prefix", "meaning": "完全", "origin": "per-"},
        {"part": "form", "type": "root", "meaning": "形成,执行", "origin": "L.forma"},
        {"part": "ance", "type": "suffix", "meaning": "性质,状态", "origin": ""},
    ],
    "permission": [
        {"part": "per", "type": "prefix", "meaning": "完全", "origin": "per-"},
        {"part": "miss", "type": "root", "meaning": "送,发", "origin": "L.mittere"},
        {"part": "ion", "type": "suffix", "meaning": "行为,状态", "origin": ""},
    ],
    "population": [
        {"part": "popul", "type": "root", "meaning": "人民", "origin": "L.populus"},
        {"part": "ation", "type": "suffix", "meaning": "行为,过程", "origin": ""},
    ],
    "possession": [
        {"part": "pos", "type": "prefix", "meaning": "能够", "origin": "L.potis"},
        {"part": "sess", "type": "root", "meaning": "坐,占有", "origin": "L.sedere"},
        {"part": "ion", "type": "suffix", "meaning": "行为,状态", "origin": ""},
    ],
    "prediction": [
        {"part": "pre", "type": "prefix", "meaning": "前,预先", "origin": "pre-"},
        {"part": "dict", "type": "root", "meaning": "说", "origin": "L.dicere"},
        {"part": "ion", "type": "suffix", "meaning": "行为,状态", "origin": ""},
    ],
    "preparation": [
        {"part": "pre", "type": "prefix", "meaning": "前,预先", "origin": "pre-"},
        {"part": "par", "type": "root", "meaning": "准备", "origin": "L.parare"},
        {"part": "ation", "type": "suffix", "meaning": "行为,过程", "origin": ""},
    ],
    "presentation": [
        {"part": "pre", "type": "prefix", "meaning": "前", "origin": "pre-"},
        {"part": "sent", "type": "root", "meaning": "存在,出现", "origin": "L.praesentare"},
        {"part": "ation", "type": "suffix", "meaning": "行为,过程", "origin": ""},
    ],
    "production": [
        {"part": "pro", "type": "prefix", "meaning": "向前", "origin": "pro-"},
        {"part": "duct", "type": "root", "meaning": "引导", "origin": "L.ducere"},
        {"part": "ion", "type": "suffix", "meaning": "行为,状态", "origin": ""},
    ],
    "profession": [
        {"part": "pro", "type": "prefix", "meaning": "向前", "origin": "pro-"},
        {"part": "fess", "type": "root", "meaning": "坦白,声明", "origin": "L.fateri"},
        {"part": "ion", "type": "suffix", "meaning": "行为,状态", "origin": ""},
    ],
    "progress": [
        {"part": "pro", "type": "prefix", "meaning": "向前", "origin": "pro-"},
        {"part": "gress", "type": "root", "meaning": "步,走", "origin": "L.gradi"},
    ],
    "promotion": [
        {"part": "pro", "type": "prefix", "meaning": "向前", "origin": "pro-"},
        {"part": "mot", "type": "root", "meaning": "移动", "origin": "L.movere"},
        {"part": "ion", "type": "suffix", "meaning": "行为,状态", "origin": ""},
    ],
    "protection": [
        {"part": "pro", "type": "prefix", "meaning": "向前", "origin": "pro-"},
        {"part": "tect", "type": "root", "meaning": "覆盖,保护", "origin": "L.tegere"},
        {"part": "ion", "type": "suffix", "meaning": "行为,状态", "origin": ""},
    ],
    "publication": [
        {"part": "publ", "type": "root", "meaning": "公共", "origin": "L.publicus"},
        {"part": "ic", "type": "suffix", "meaning": "…的", "origin": ""},
        {"part": "ation", "type": "suffix", "meaning": "行为,过程", "origin": ""},
    ],
    "reception": [
        {"part": "re", "type": "prefix", "meaning": "回", "origin": "re-"},
        {"part": "cept", "type": "root", "meaning": "拿,取", "origin": "L.capere"},
        {"part": "ion", "type": "suffix", "meaning": "行为,状态", "origin": ""},
    ],
    "recognition": [
        {"part": "re", "type": "prefix", "meaning": "再", "origin": "re-"},
        {"part": "cogn", "type": "root", "meaning": "知道", "origin": "L.cognoscere"},
        {"part": "ition", "type": "suffix", "meaning": "行为,状态", "origin": ""},
    ],
    "recommendation": [
        {"part": "re", "type": "prefix", "meaning": "再", "origin": "re-"},
        {"part": "com", "type": "prefix", "meaning": "完全", "origin": "com-"},
        {"part": "mend", "type": "root", "meaning": "命令,委托", "origin": "L.mandare"},
        {"part": "ation", "type": "suffix", "meaning": "行为,过程", "origin": ""},
    ],
    "reduction": [
        {"part": "re", "type": "prefix", "meaning": "回", "origin": "re-"},
        {"part": "duct", "type": "root", "meaning": "引导", "origin": "L.ducere"},
        {"part": "ion", "type": "suffix", "meaning": "行为,状态", "origin": ""},
    ],
    "reference": [
        {"part": "re", "type": "prefix", "meaning": "回", "origin": "re-"},
        {"part": "fer", "type": "root", "meaning": "带,承载", "origin": "L.ferre"},
        {"part": "ence", "type": "suffix", "meaning": "性质,状态", "origin": ""},
    ],
    "reflection": [
        {"part": "re", "type": "prefix", "meaning": "回", "origin": "re-"},
        {"part": "flect", "type": "root", "meaning": "弯曲", "origin": "L.flectere"},
        {"part": "ion", "type": "suffix", "meaning": "行为,状态", "origin": ""},
    ],
    "relationship": [
        {"part": "re", "type": "prefix", "meaning": "回", "origin": "re-"},
        {"part": "lat", "type": "root", "meaning": "带来", "origin": "L.latus"},
        {"part": "ion", "type": "suffix", "meaning": "行为,状态", "origin": ""},
        {"part": "ship", "type": "suffix", "meaning": "身份,关系", "origin": ""},
    ],
    "represent": [
        {"part": "re", "type": "prefix", "meaning": "再", "origin": "re-"},
        {"part": "pre", "type": "prefix", "meaning": "前", "origin": "pre-"},
        {"part": "sent", "type": "root", "meaning": "存在", "origin": "L.praesentare"},
    ],
    "requirement": [
        {"part": "re", "type": "prefix", "meaning": "再", "origin": "re-"},
        {"part": "quir", "type": "root", "meaning": "寻找", "origin": "L.quaerere"},
        {"part": "ment", "type": "suffix", "meaning": "行为,结果", "origin": ""},
    ],
    "resolution": [
        {"part": "re", "type": "prefix", "meaning": "再", "origin": "re-"},
        {"part": "solut", "type": "root", "meaning": "松开", "origin": "L.solvere"},
        {"part": "ion", "type": "suffix", "meaning": "行为,状态", "origin": ""},
    ],
    "responsibility": [
        {"part": "re", "type": "prefix", "meaning": "回", "origin": "re-"},
        {"part": "spons", "type": "root", "meaning": "承诺,回应", "origin": "L.spondere"},
        {"part": "ibil", "type": "suffix", "meaning": "能…的", "origin": ""},
        {"part": "ity", "type": "suffix", "meaning": "性质,状态", "origin": ""},
    ],
    "revolution": [
        {"part": "re", "type": "prefix", "meaning": "回", "origin": "re-"},
        {"part": "volut", "type": "root", "meaning": "卷,转", "origin": "L.volvere"},
        {"part": "ion", "type": "suffix", "meaning": "行为,状态", "origin": ""},
    ],
    "satisfaction": [
        {"part": "satis", "type": "root", "meaning": "足够", "origin": "L.satis"},
        {"part": "fact", "type": "root", "meaning": "做", "origin": "L.facere"},
        {"part": "ion", "type": "suffix", "meaning": "行为,状态", "origin": ""},
    ],
    "situation": [
        {"part": "situ", "type": "root", "meaning": "位置", "origin": "L.situs"},
        {"part": "ation", "type": "suffix", "meaning": "行为,过程", "origin": ""},
    ],
    "suggestion": [
        {"part": "sug", "type": "prefix", "meaning": "下", "origin": "sub-"},
        {"part": "gest", "type": "root", "meaning": "搬运,带来", "origin": "L.gerere"},
        {"part": "ion", "type": "suffix", "meaning": "行为,状态", "origin": ""},
    ],
    "temperature": [
        {"part": "temper", "type": "root", "meaning": "调节,适度", "origin": "L.temperare"},
        {"part": "ature", "type": "suffix", "meaning": "行为,状态", "origin": ""},
    ],
    "tradition": [
        {"part": "tra", "type": "prefix", "meaning": "穿越", "origin": "trans-"},
        {"part": "dit", "type": "root", "meaning": "给", "origin": "L.dare"},
        {"part": "ion", "type": "suffix", "meaning": "行为,状态", "origin": ""},
    ],
    "transportation": [
        {"part": "trans", "type": "prefix", "meaning": "穿越", "origin": "trans-"},
        {"part": "port", "type": "root", "meaning": "携带", "origin": "L.portare"},
        {"part": "ation", "type": "suffix", "meaning": "行为,过程", "origin": ""},
    ],
    "uncomfortable": [
        {"part": "un", "type": "prefix", "meaning": "不", "origin": "un-"},
        {"part": "com", "type": "prefix", "meaning": "完全", "origin": "com-"},
        {"part": "fort", "type": "root", "meaning": "强", "origin": "L.fortis"},
        {"part": "able", "type": "suffix", "meaning": "能…的", "origin": ""},
    ],
    "understanding": [
        {"part": "under", "type": "prefix", "meaning": "在下", "origin": "under-"},
        {"part": "stand", "type": "root", "meaning": "站立", "origin": "OE.standan"},
        {"part": "ing", "type": "suffix", "meaning": "行为,过程", "origin": ""},
    ],
    "unfortunately": [
        {"part": "un", "type": "prefix", "meaning": "不", "origin": "un-"},
        {"part": "fortun", "type": "root", "meaning": "运气", "origin": "L.fortuna"},
        {"part": "ate", "type": "suffix", "meaning": "…的", "origin": ""},
        {"part": "ly", "type": "suffix", "meaning": "…地", "origin": ""},
    ],
}


# ══════════════════════════════════════════════════════════════
# 分解引擎：动态规划 + 贪心回溯
# ══════════════════════════════════════════════════════════════

def _try_match_prefix(word: str) -> list[tuple[str, dict]]:
    """尝试匹配前缀，返回所有可能的 (剩余部分, morpheme_dict) 列表，按长度降序"""
    results = []
    for length in range(min(7, len(word) - 2), 0, -1):  # 前缀最长7字符，至少留2字符给词根
        candidate = word[:length]
        if candidate in PREFIXES:
            cn, en, origin = PREFIXES[candidate]
            results.append((word[length:], {
                "part": candidate,
                "type": "prefix",
                "meaning": cn,
                "origin": origin,
            }))
    return results


def _try_match_suffix(word: str) -> list[tuple[str, dict]]:
    """尝试匹配后缀，返回所有可能的 (剩余部分, morpheme_dict) 列表，按长度降序"""
    results = []
    for length in range(min(5, len(word) - 2), 0, -1):  # 后缀最长5字符
        candidate = word[-length:]
        if candidate in SUFFIXES:
            cn, pos, en = SUFFIXES[candidate]
            results.append((word[:-length], {
                "part": candidate,
                "type": "suffix",
                "meaning": cn,
                "origin": "",
            }))
    return results


def _try_match_root(word: str) -> list[tuple[int, int, dict]]:
    """在 word 中尝试匹配词根，返回 (start, end, morpheme_dict) 列表"""
    results = []
    for length in range(min(7, len(word)), 1, -1):
        for start in range(0, len(word) - length + 1):
            candidate = word[start:start + length]
            if candidate in ROOTS:
                cn, en, origin = ROOTS[candidate]
                results.append((start, start + length, {
                    "part": candidate,
                    "type": "root",
                    "meaning": cn,
                    "origin": origin,
                }))
    return results


def _decompose_algorithmically(word: str) -> Optional[list[dict]]:
    """
    使用算法分解单词。
    策略: 贪心 — 先尝试最长前缀，再尝试最长后缀，中间匹配词根。
    """
    w = word.lower().strip()
    if len(w) < 4:  # 太短的词不分解
        return None

    best_result = None
    best_score = 0

    # 尝试不同的前缀 × 后缀组合
    prefix_options = _try_match_prefix(w)
    prefix_options.append((w, None))  # 也尝试无前缀

    for remaining_after_prefix, prefix_morpheme in prefix_options:
        suffix_options = _try_match_suffix(remaining_after_prefix)
        suffix_options.append((remaining_after_prefix, None))  # 也尝试无后缀

        for middle, suffix_morpheme in suffix_options:
            if len(middle) < 2:
                continue

            # 尝试在 middle 中找词根
            root_matches = _try_match_root(middle)

            for start, end, root_morpheme in root_matches:
                # 构建分解结果
                result = []
                covered = 0

                if prefix_morpheme:
                    result.append(prefix_morpheme)
                    covered += len(prefix_morpheme["part"])

                # 词根前面有未匹配的部分 → 可能是连接字母，跳过
                if start > 0:
                    leftover_before = middle[:start]
                    if len(leftover_before) > 2:
                        continue  # 未解释部分太多，放弃这个组合
                    # 小的未解释部分容忍

                result.append(root_morpheme)
                covered += len(root_morpheme["part"])

                # 词根后面有未匹配的部分
                if end < len(middle):
                    leftover_after = middle[end:]
                    if len(leftover_after) > 2:
                        # 尝试在剩余部分找第二个后缀
                        sub_suffix = _try_match_suffix(middle[start:])
                        found_sub = False
                        for sub_rem, sub_suf_m in sub_suffix:
                            if sub_rem == root_morpheme["part"] or sub_rem.startswith(root_morpheme["part"]):
                                # 加入额外的后缀
                                result.append(sub_suf_m)
                                covered += len(sub_suf_m["part"])
                                found_sub = True
                                break
                        if not found_sub:
                            continue

                if suffix_morpheme:
                    result.append(suffix_morpheme)
                    covered += len(suffix_morpheme["part"])

                # 评分：覆盖率
                coverage = covered / len(w)
                # 至少要有一个词根
                has_root = any(m["type"] == "root" for m in result)
                # 至少覆盖60%
                if has_root and coverage >= 0.6 and len(result) >= 2:
                    score = coverage * 100 + len(result) * 5
                    if score > best_score:
                        best_score = score
                        best_result = result

    return best_result


def decompose_word(word: str) -> Optional[list[dict]]:
    """
    分解单词为词根词缀。
    优先使用手工标注数据，回退到算法分解。
    返回 None 表示无法分解（短词、短语等）。
    """
    w = word.lower().strip()

    # 短语不分解
    if ' ' in w or '-' in w:
        return None

    # 太短的词不分解
    if len(w) < 4:
        return None

    # 1. 优先手工标注
    if w in MANUAL_MORPHEMES:
        return MANUAL_MORPHEMES[w]

    # 2. 算法分解
    result = _decompose_algorithmically(w)
    return result


def get_morphemes(word: str) -> Optional[list[dict]]:
    """供 main.py 调用的入口函数"""
    return decompose_word(word)


# ══════════════════════════════════════════════════════════════
# 测试 / CLI
# ══════════════════════════════════════════════════════════════

if __name__ == "__main__":
    test_words = [
        "acceptance", "accident", "comfortable", "uncomfortable",
        "education", "information", "international", "construction",
        "production", "description", "confidence", "experience",
        "expression", "impression", "transportation", "beautiful",
        "prediction", "revolution", "performance", "relationship",
        "immediately", "independence", "responsibility", "instruction",
    ]

    for w in test_words:
        result = decompose_word(w)
        if result:
            parts = " + ".join(
                f"{m['part']}({m['meaning']})" for m in result
            )
            print(f"  {w:20s} → {parts}")
        else:
            print(f"  {w:20s} → [无法分解]")
