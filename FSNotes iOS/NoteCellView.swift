//
//  NoteCellView.swift
//  FSNotes iOS
//
//  Created by Oleksandr Glushchenko on 1/29/18.
//  Copyright © 2018 Oleksandr Glushchenko. All rights reserved.
//

import UIKit

class NoteCellView: UITableViewCell {
    @IBOutlet weak var title: UILabel!
    @IBOutlet weak var date: UILabel!
    @IBOutlet weak var preview: UILabel!
    
    func configure(note: Note) {
        title.attributedText = NSAttributedString(string: note.title)
        preview.attributedText = NSAttributedString(string: note.getPreviewForLabel())
        date.attributedText = NSAttributedString(string: note.getDateForLabel())
    }
}
