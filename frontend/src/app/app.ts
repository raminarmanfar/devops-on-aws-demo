import { Component, signal, OnInit } from '@angular/core';
import { RouterOutlet } from '@angular/router';
import { HelloService } from './services/hello.service';

@Component({
  selector: 'app-root',
  imports: [RouterOutlet],
  templateUrl: './app.html',
  styleUrl: './app.css'
})
export class App implements OnInit {
  message = signal('');

  constructor(private helloService: HelloService) {}

  ngOnInit(): void {
    this.helloService.getMessage().subscribe({
      next: (msg) => this.message.set(msg),
      error: () => this.message.set('Failed to load message from backend.')
    });
  }
}
