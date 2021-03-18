//
//  ContentView.swift
//  AckeeExample
//
//  Created by Leonard Mehlig on 17.03.21.
//

import SwiftUI
import Ackee
import Combine

struct ContentView: View {

    @StateObject var tracker = Tracker(url: URL(string: "https://stats.example.com/api")!,
                                       domain: "domain_id")

    @State var isPresented: Bool = false

    var body: some View {
        Button("Show Sheet") {
            isPresented = true
        }
        .sheet(isPresented: $isPresented, content: {
            Sheet()
        })
        .environmentObject(tracker)
    }
}

extension Event {
    static let purchase = Event(id: "eventId", key: "Price")
}

struct Sheet: View {
    @EnvironmentObject var tracker: Tracker

    @State var record: Ackee.Record?

    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        VStack {

            Button("Buy") {
                self.tracker.action(.purchase, value: 5)
            }

            Button("Dismiss") {
                self.presentationMode.wrappedValue.dismiss()
            }
            .onAppear {
                tracker.record(path: "app.structured.today/sheet", to: \.record, on: self)
            }
            .onDisappear {
                tracker.update(record: record)
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
