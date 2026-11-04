import Foundation

/// Prompts and deterministic fallback follow Android TextPolisher 1.5.9.
public enum VoicePrompts {
  public static func relationRule(_ relation: String) -> String {
    switch relation {
    case "心动对象": "心动对象；语气自然、有吸引力但不过度热情，不擅自确认关系"
    case "恋人": "恋人；语气亲密温暖，可以自然表达关心，但不编造承诺"
    case "朋友": "朋友；语气轻松真诚，避免暧昧和越界表达"
    default: "通用聊天对象；语气自然、礼貌、有分寸"
    }
  }
  public static func prompt(style: String, settings: Settings, relation: String = "通用", deep: Bool) -> String {
    let terms = settings.professional.prefix(deep ? 96 : 24).map {
      $0.hint.isEmpty ? $0.term : "\($0.term)（\($0.hint)）"
    }.joined(separator: "；")
    if !deep {
      let styleRule = style == "办公正式" ? "偏正式。" : style == "笔记简洁" ? "简洁笔记。" : "自然口语。"
      let punctuationRule = settings.punctuation == "空格代替标点" ? "标点改空格。" : settings.punctuation == "句末不添加标点" ? "末尾不要标点。" : "补标点。"
      var result = "润色语音转写，\(styleRule) \(punctuationRule) 去掉嗯啊、明显重复和口误；保留数字、日期、英文、专名；不增事实；只输出正文。 对方关系：\(relationRule(relation))。"
      if !terms.isEmpty { result += " 术语：\(terms)。" }
      return result
    }
    let styleRule = style == "办公正式" ? "改写为正式、清晰的办公表达。" : style == "笔记简洁" ? "整理为简洁笔记；内容并列时优先分点或分段。" : "改写为自然、口语化但简洁的聊天表达。"
    let punctuationRule = settings.punctuation == "空格代替标点" ? "将输出里的标点替换为空格，并合并多余空格。" : settings.punctuation == "句末不添加标点" ? "保留句内标点，但删除最终文本末尾的标点。" : "按语义补全并优化标点。"
    let structureRule = settings.optimizeExpression ? optimizedStructure : forcedStructure
    let lexiconRule = terms.isEmpty ? "无" : terms
    return """
    你是中文语音转写编辑。
    对方关系：\(relationRule(relation))。
    \(styleRule)
    \(punctuationRule)
    \(structureRule)
    删除无意义语气词、明显重复和自我纠正，但必须保留人名、数字、日期、英文、代码、品牌名和专业术语。
    不得补充事实，不得改变核心含义。
    只输出整理后的正文，不要标题、解释或引号。
    专业词库：\(lexiconRule)。
    """
  }
  private static let forcedStructure = """
    这段口述已被判定为结构化内容。必须真正换行输出，不能只补标点或空格后仍保留为一段连续文字。
    结构判断：只有 1 件事用完整段落；有 2 件及以上可区分事项时必须编号；3 件以上且存在不同主题时先按主题分组。
    同一类待办、步骤或清单保持扁平列表，使用“1.内容”“2.内容”“3.内容”；不同主题才使用一级主题和缩进的“(a)内容”“(b)内容”。
    将“一是、二是、三是”“第一、第二、第三”“首先、其次、最后”“包括、分别是、原因有、分为”等标记和中文停顿拆成独立条目。
    有总述时先保留总述并以冒号结束，再换行列出条目；括号中的补充说明写为对应条目下的“备注：”。
    不得凭空增加事项、主题、事实或结论；不得把用户的问题改成答案。
    示例：
    输入：今天要做三件事，第一睡觉，第二刷牙，第三洗澡
    输出：
    今天要做三件事：
    1.睡觉
    2.刷牙
    3.洗澡
    """
  private static let optimizedStructure = """
    当口述包含分类、分点、步骤、待办、提纲、框架、并列事项或“包括/原因有/分为”等结构信号时，必须整理成真正换行的编号列表。
    两个及以上事项使用 1.、2.、3.；同类事项保持扁平，不要为了复杂而强行分组；不同主题才增加主题层和 (a)、(b) 子项。
    对含有“一是/二是/三是、第一/第二/第三、首先/其次/最后、分别是”等标记的内容，不能只补标点后保留为连续段落。
    保留全部原意，不补充新事实。括号中的补充说明优先整理成对应条目的“备注：”。
    对观点对立类作文框架，按开头段、中间段、结尾段分组，再拆成可读子项。
    """
  public static let translation = "将用户文本翻译为自然、准确的美式英语。保留原意、数字、专有名词和段落；只输出译文，不要解释或添加引号。"
  public static func localFallback(_ text: String) -> String {
    text.replacingOccurrences(of: "[，,。.!！?？；;：:、]{2,}", with: "。", options: .regularExpression)
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .replacingOccurrences(of: "^(嗯+|啊+|呃+|额+|那个|就是)[，,。.!！?？；;：:\\s]*", with: "", options: .regularExpression)
      .replacingOccurrences(of: "[\\s，,。.!！?？；;：:、]*(嗯+|啊+|呃+|额+)[\\s，,。.!！?？；;：:、]*", with: "", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
