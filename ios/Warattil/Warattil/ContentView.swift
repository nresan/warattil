//
//  ContentView.swift
//  Warattil
//
//  Root view after bootstrap. Owns the MushaFViewModel and hands it to
//  MushaFScreen. Construction happens here (not in WarattilApp) so the
//  VM's lifecycle is tied to the visible root — simulator state restoration
//  wipes this view's @State, which is the correct granularity.
//

import SwiftUI

struct ContentView: View {
    // @State on a reference type with @Observable — SwiftUI tracks field-
    // level changes on the VM automatically. No @StateObject / ObservableObject.
    @State private var viewModel = MushaFViewModel()

    var body: some View {
        MushaFScreen(viewModel: viewModel)
    }
}

#Preview {
    ContentView()
}
