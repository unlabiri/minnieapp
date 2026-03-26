//
//  ContentView.swift
//  MinnieApp
//
//  Created by Ada Aljabiri on 3/24/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            JinaDJBoard()
                .tabItem {Label("Jina", systemImage: "list.dash") //
                                }
            AdaDJBoard()
                .tabItem {
                    Label("Ada", systemImage: "list.dash")
                }
            
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
