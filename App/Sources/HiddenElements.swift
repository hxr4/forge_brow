import Foundation

/// Per-site CSS selectors the user hid with "Hide This Element".
enum HiddenElements {
    private static let key = "forge.hiddenElements"

    private static var rules: [String: [String]] {
        get { UserDefaults.standard.dictionary(forKey: key) as? [String: [String]] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static func host(of url: String) -> String? {
        guard let host = URL(string: url)?.host?.lowercased(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static func selectors(for url: String) -> [String] {
        guard let host = host(of: url) else { return [] }
        return rules[host] ?? []
    }

    static func add(_ selector: String, for url: String) {
        guard let host = host(of: url), !selector.isEmpty else { return }
        var all = rules
        var list = all[host] ?? []
        guard !list.contains(selector) else { return }
        list.append(selector)
        all[host] = list
        rules = all
    }

    static func clear(for url: String) {
        guard let host = host(of: url) else { return }
        var all = rules
        all.removeValue(forKey: host)
        rules = all
    }

    /// Installs (or clears) the style sheet that keeps this site's elements hidden.
    static func injectionScript(for url: String) -> String {
        let css = selectors(for: url).map { $0 + "{display:none !important}" }.joined(separator: "\n")
        let literal = (try? String(data: JSONSerialization.data(withJSONObject: [css]), encoding: .utf8))
            .map { String($0.dropFirst().dropLast()) } ?? "\"\""
        return """
        (function(){var id='__forge_hidden__';var s=document.getElementById(id);
        var css=\(literal);
        if(!css){if(s)s.remove();return;}
        if(!s){s=document.createElement('style');s.id=id;(document.head||document.documentElement).appendChild(s);}
        s.textContent=css;})();
        """
    }

    /// Hides the element under a CSS point and returns a selector for it. Walks up
    /// through single-child wrappers so the whole box goes, not just its inner image.
    static func pickScript(at x: CGFloat, _ y: CGFloat) -> String {
        """
        (function(x,y){
          var el=document.elementFromPoint(x,y);
          if(!el||el===document.body||el===document.documentElement) return null;
          while(el.parentElement&&el.parentElement!==document.body&&el.parentElement.children.length===1){
            el=el.parentElement;
          }
          var ok=/^[A-Za-z_][\\w-]*$/;
          function part(e){
            if(e.id&&ok.test(e.id)) return '#'+e.id;
            var p=e.tagName.toLowerCase();
            var cls=[].slice.call(e.classList).filter(function(c){return ok.test(c)&&c.length<40;}).slice(0,2);
            if(cls.length) p+='.'+cls.join('.');
            var parent=e.parentElement;
            if(parent){
              var same=[].slice.call(parent.children).filter(function(c){return c.tagName===e.tagName;});
              if(same.length>1) p+=':nth-of-type('+(same.indexOf(e)+1)+')';
            }
            return p;
          }
          var parts=[],cur=el;
          while(cur&&cur.nodeType===1&&cur!==document.body&&parts.length<6){
            var p=part(cur);parts.unshift(p);
            if(p.charAt(0)==='#') break;
            cur=cur.parentElement;
          }
          var sel=parts.join(' > ');
          el.style.setProperty('display','none','important');
          return sel;
        })(\(Int(x)),\(Int(y)))
        """
    }
}
