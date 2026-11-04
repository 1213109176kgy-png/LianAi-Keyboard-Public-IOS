import LianAiCore
import SwiftUI

extension Color {
  init(hex: UInt32) {
    self.init(
      red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255,
      blue: Double(hex & 255) / 255)
  }
}
enum LA {
  static let accent = Color(
    uiColor: UIColor {
      $0.userInterfaceStyle == .dark
        ? UIColor(red: 1, green: 0.490, blue: 0.663, alpha: 1)
        : UIColor(red: 1, green: 0.420, blue: 0.616, alpha: 1)
    })
  static let orange = Color(hex: 0xFFA07A)
  static let gradient = LinearGradient(
    colors: [Color(hex: 0xFF6B9D), orange], startPoint: .topLeading, endPoint: .bottomTrailing)
  static let background = Color(
    uiColor: UIColor {
      $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.149, green: 0.110, blue: 0.129, alpha: 1)
        : UIColor(red: 1, green: 0.976, blue: 0.980, alpha: 1)
    })
  static let panel = Color(
    uiColor: UIColor {
      $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.204, green: 0.149, blue: 0.176, alpha: 1) : .white
    })
  static let key = Color(
    uiColor: UIColor {
      $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.325, green: 0.220, blue: 0.267, alpha: 1)
        : UIColor(red: 1, green: 0.910, blue: 0.933, alpha: 1)
    })
  static let ink = Color(
    uiColor: UIColor {
      $0.userInterfaceStyle == .dark
        ? UIColor(red: 1, green: 0.969, blue: 0.980, alpha: 1)
        : UIColor(red: 0.176, green: 0.204, blue: 0.212, alpha: 1)
    })
  static let muted = Color(
    uiColor: UIColor {
      $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.847, green: 0.749, blue: 0.788, alpha: 1)
        : UIColor(red: 0.553, green: 0.494, blue: 0.518, alpha: 1)
    })
}
struct Icon: View {
  let name: String
  var size: CGFloat = 22
  var body: some View {
    Image("lucide_" + name).resizable().renderingMode(.template).scaledToFit().frame(
      width: size, height: size
    ).accessibilityHidden(true)
  }
}
struct Card<Content: View>: View {
  var padding: CGFloat = 14
  var spacing: CGFloat = 12
  var radius: CGFloat = 24
  var border: Color? = nil
  @ViewBuilder var content: Content
  var body: some View {
    VStack(alignment: .leading, spacing: spacing) { content }.padding(.vertical, padding)
      .padding(.horizontal, padding == 14 ? 18 : padding).frame(
      maxWidth: .infinity, alignment: .leading
    ).background(LA.panel, in: RoundedRectangle(cornerRadius: radius))
      .overlay(RoundedRectangle(cornerRadius: radius).stroke(border ?? .clear, lineWidth: 1))
  }
}
struct SectionLabel: View {
  let text: String
  init(_ text: String) { self.text = text }
  var body: some View {
    Text(text).font(.system(size: 14, weight: .bold)).foregroundStyle(LA.ink).padding(.top, 18)
      .padding(.bottom, 0).frame(maxWidth: .infinity, alignment: .leading)
  }
}
struct ActionRow: View {
  var title: String
  var detail = ""
  var icon: String?
  var destructive = false
  var action: () -> Void
  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        if let icon {
          Icon(name: icon, size: 18).foregroundStyle(LA.accent).frame(width: 34, height: 34)
            .background(LA.accent.opacity(0.15), in: Circle())
        }
        VStack(alignment: .leading, spacing: 0) {
          Text(title).font(.system(size: 14)).foregroundStyle(
            destructive ? .red : LA.ink)
          if !detail.isEmpty { Text(detail).font(.system(size: 12)).foregroundStyle(LA.muted) }
        }
        Spacer(minLength: 4)
        Icon(name: "chevron_right", size: 20).foregroundStyle(LA.muted).frame(width: 34, height: 48)
      }.padding(.vertical, 6).contentShape(Rectangle())
    }.buttonStyle(.plain)
  }
}
struct LAButton: View {
  var title: String
  var filled = true
  var busy = false
  var height: CGFloat = 48
  var radius: CGFloat = 24
  var fontSize: CGFloat = 14
  var tint: Color = LA.accent
  var soft: Color = LA.key
  var action: () -> Void
  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        if busy { ProgressView().tint(filled ? .white : tint) }
        Text(title).font(.system(size: fontSize))
      }.frame(maxWidth: .infinity).frame(minHeight: height).foregroundStyle(filled ? .white : tint)
        .background(filled ? tint : soft, in: RoundedRectangle(cornerRadius: radius))
    }.buttonStyle(.plain).disabled(busy)
  }
}
struct Segments: View {
  let labels: [String]
  @Binding var value: String
  var body: some View {
    HStack(spacing: 3) {
      ForEach(labels, id: \.self) { label in
        Button {
          value = label
        } label: {
          Text(label).font(.system(size: 12, weight: value == label ? .bold : .regular)).lineLimit(
            1
          ).minimumScaleFactor(0.65).frame(maxWidth: .infinity).frame(height: 40).foregroundStyle(
            value == label ? .white : LA.muted
          ).background(value == label ? LA.accent : .clear, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain)
      }
    }.padding(3).background(LA.key, in: RoundedRectangle(cornerRadius: 15))
  }
}
struct Field: View {
  var title: String
  @Binding var text: String
  var secure = false
  var body: some View {
    Group {
      if secure {
        SecureField(title, text: $text)
      } else {
        TextField(title, text: $text).textInputAutocapitalization(.never).autocorrectionDisabled()
      }
    }.font(.system(size: 14)).padding(.horizontal, 14).frame(height: 48).background(
      LA.key, in: RoundedRectangle(cornerRadius: 13)
    ).foregroundStyle(LA.ink)
  }
}
struct Hint: View {
  let text: String
  init(_ text: String) { self.text = text }
  var body: some View {
    Text(text).font(.system(size: 12)).lineSpacing(4).foregroundStyle(LA.muted).fixedSize(
      horizontal: false, vertical: true)
  }
}
struct SettingToggle: View {
  let title: String
  let guide: String
  @Binding var value: Bool
  var body: some View {
    Card(spacing: 0) {
      OperationGuide(text: guide)
      Toggle(title, isOn: $value).font(.system(size: 14, weight: .bold)).tint(LA.accent).frame(height: 42)
    }
  }
}
struct KeyboardPreview: View {
  var size = 18
  var body: some View {
    VStack(spacing: 6) {
      HStack {
        Text("你好").foregroundStyle(LA.accent)
        Text("你们")
        Text("您好")
        Spacer()
        Icon(name: "chevron_right", size: 16)
      }.font(.system(size: CGFloat(size))).padding(8)
      ForEach(["QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM"], id: \.self) { letters in
        HStack(spacing: 4) {
          ForEach(Array(letters), id: \.self) { letter in
            Text(String(letter)).font(.system(size: 10)).frame(maxWidth: .infinity).frame(
              height: 24
            ).background(LA.panel, in: RoundedRectangle(cornerRadius: 5))
          }
        }
      }
      Text("恋爱键盘").font(.system(size: 10)).frame(width: 120, height: 23).background(
        LA.panel, in: RoundedRectangle(cornerRadius: 5))
    }.foregroundStyle(LA.ink).padding(10).background(LA.key, in: RoundedRectangle(cornerRadius: 16))
  }
}

struct AppModal<ModalContent: View>: ViewModifier {
  @Binding var presented: Bool
  var alignment: Alignment = .center
  var dim: Double = 0.34
  @ViewBuilder var modal: () -> ModalContent
  func body(content: Content) -> some View {
    content.fullScreenCover(isPresented: $presented) {
      GeometryReader { geometry in
        ZStack(alignment: alignment) {
          Color.black.opacity(dim).ignoresSafeArea().onTapGesture { presented = false }
          ScrollView {
            modal().padding(22)
          }.scrollBounceBehavior(.basedOnSize)
            .frame(maxWidth: 460, maxHeight: geometry.size.height * 0.84)
            .fixedSize(horizontal: false, vertical: true)
            .background(LA.panel, in: RoundedRectangle(cornerRadius: 26))
            .padding(.horizontal, alignment == .bottom ? 16 : 24)
            .padding(.bottom, alignment == .bottom ? 16 : 0)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
      }.presentationBackground(.clear).foregroundStyle(LA.ink)
    }
  }
}
extension View {
  func appModal<Content: View>(isPresented: Binding<Bool>, alignment: Alignment = .center, dim: Double = 0.34, @ViewBuilder content: @escaping () -> Content) -> some View {
    modifier(AppModal(presented: isPresented, alignment: alignment, dim: dim, modal: content))
  }
}
struct ChoiceField: View {
  let title: String
  let choices: [String]
  @Binding var value: String
  @State private var choosing = false
  var body: some View {
    Button { choosing = true } label: {
      HStack {
        Text(value).font(.system(size: 14)).foregroundStyle(LA.ink)
        Spacer()
        Icon(name: "chevron_down", size: 18).foregroundStyle(LA.muted)
      }.padding(.horizontal, 14).frame(height: 48)
        .background(LA.key, in: RoundedRectangle(cornerRadius: 12))
    }.buttonStyle(.plain).accessibilityLabel(title + "，" + value).accessibilityIdentifier(title)
      .appModal(isPresented: $choosing) {
        VStack(alignment: .leading, spacing: 8) {
          Text(title).font(.system(size: 18, weight: .bold)).padding(.bottom, 10)
          ForEach(choices, id: \.self) { choice in
            Button { value = choice; choosing = false } label: {
              HStack {
                Text(choice).font(.system(size: 14))
                Spacer()
                if choice == value { Image(systemName: "checkmark").font(.system(size: 18)).accessibilityHidden(true) }
              }.foregroundStyle(choice == value ? LA.accent : LA.ink)
                .padding(.horizontal, 14).frame(minHeight: 48)
                .background(choice == value ? LA.key : .clear, in: RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain)
          }
          LAButton(title: "取消", filled: false) { choosing = false }
        }
      }
  }
}
struct OperationGuide: View {
  let text: String
  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      RoundedRectangle(cornerRadius: 2).fill(LA.accent).frame(width: 3)
      VStack(alignment: .leading, spacing: 4) {
        let lines = text.components(separatedBy: "\n")
        Text(lines.first ?? "").font(.system(size: 14, weight: .bold)).foregroundStyle(LA.ink)
        if lines.count > 1 { Hint(lines.dropFirst().joined(separator: "\n")) }
      }.frame(maxWidth: .infinity, alignment: .leading)
    }.fixedSize(horizontal: false, vertical: true).padding(.vertical, 5.5).padding(.bottom, 12)
  }
}

struct SettingTitle: View {
  let title: String
  init(_ title: String) { self.title = title }
  var body: some View {
    Text(title).font(.system(size: 14, weight: .bold)).frame(height: 42).frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct BrandSlider: View {
  @Binding var value: Double
  var body: some View {
    GeometryReader { geometry in
      let width = max(1, geometry.size.width - 26)
      let progress = min(1, max(0, value))
      ZStack(alignment: .leading) {
        Capsule().fill(LA.key).frame(height: 18)
        Capsule().fill(LA.accent).frame(width: geometry.size.width * progress, height: 18)
        Circle().fill(.white).overlay(Circle().stroke(Color.gray, lineWidth: 1))
          .shadow(color: .black.opacity(0.12), radius: 1, y: 1).frame(width: 26, height: 26)
          .offset(x: width * progress)
      }.frame(maxHeight: .infinity).contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { event in value = min(1, max(0, (event.location.x - 13) / width)) })
    }.frame(height: 48).accessibilityElement().accessibilityLabel("按键音量")
      .accessibilityValue("\(Int(value * 100))%")
      .accessibilityAdjustableAction { direction in
        value = min(1, max(0, value + (direction == .increment ? 0.05 : -0.05)))
      }
  }
}
